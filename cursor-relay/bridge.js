const sqlite3 = require('sqlite3').verbose();
const WebSocket = require('ws');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const cursorAutomation = require('./cursorAutomation');

// Config
const DB_PATH = path.join(os.homedir(), 'Library/Application Support/Cursor/User/globalStorage/state.vscdb');
const PORT = 8080;
const wss = new WebSocket.Server({ port: PORT });

// Connected iOS clients
const clients = new Set();

// Change detection - only broadcast when data changes
let lastPayloadHash = null;

console.log(`🚀 Bridge Active on ws://localhost:${PORT}`);

// --- DATABASE POLLING ---
// TODO: Optimize - current implementation re-reads entire DB on each poll.
// Should instead:
//   1. Cache parsed conversations in memory
//   2. Track last-seen row count or modification time
//   3. Only query new/changed rows (e.g., WHERE rowid > lastSeenRowId)
//   4. Incrementally update the cached state
// This would significantly reduce CPU/memory usage for large chat histories.
function pollCursorDB() {
    const db = new sqlite3.Database(DB_PATH, sqlite3.OPEN_READONLY, (err) => {
        if (err) {
            console.error("❌ Failed to open database:", err.message);
            return;
        }
    });

    const query = `SELECT key, value FROM cursorDiskKV WHERE key LIKE 'composerData:%' OR key LIKE 'bubbleId:%'`;

    db.all(query, [], (err, rows) => {
        if (err) {
            console.error("❌ Query error:", err.message);
            db.close();
            return;
        }
        
        if (!rows || rows.length === 0) {
            db.close();
            return;
        }

        let conversations = {};

        // First pass: Find all composer/conversation headers
        rows.forEach(row => {
            if (row.key.startsWith('composerData:')) {
                try {
                    const data = JSON.parse(row.value);
                    if (!data) return;
                    const composerId = row.key.replace('composerData:', '');
                    const createdAt = data.createdAt ? new Date(data.createdAt).getTime() : 0;
                    conversations[composerId] = {
                        id: composerId,
                        name: data.name || data.text || "New Chat", // Don't truncate - use full name
                        timestamp: createdAt,  // Will be updated to latest message time
                        messages: []
                    };
                } catch (e) {
                    // Skip malformed entries
                }
            }
        });

        // Second pass: Attach bubbles to the correct conversation
        rows.forEach(row => {
            if (row.key.startsWith('bubbleId:')) {
                try {
                    const data = JSON.parse(row.value);
                    const keyParts = row.key.split(':');
                    const composerId = keyParts[1];
                    
                    if (!conversations[composerId]) {
                        conversations[composerId] = {
                            id: composerId,
                            name: "Chat",
                            timestamp: 0,  // Will be set from first message's createdAt
                            messages: []
                        };
                    }
                    
                    if (data.text) {
                        conversations[composerId].messages.push({
                            text: data.text,
                            isUser: data.type === 1,
                            createdAt: data.createdAt
                        });
                        if (data.createdAt) {
                            const msgTime = new Date(data.createdAt).getTime();
                            if (msgTime > conversations[composerId].timestamp) {
                                conversations[composerId].timestamp = msgTime;
                            }
                        }
                    }
                } catch (e) {
                    // Skip malformed entries
                }
            }
        });

        // Sort messages within each conversation
        Object.values(conversations).forEach(convo => {
            convo.messages.sort((a, b) => {
                const timeA = a.createdAt ? new Date(a.createdAt).getTime() : 0;
                const timeB = b.createdAt ? new Date(b.createdAt).getTime() : 0;
                return timeA - timeB;
            });
            if (convo.name === "Chat" && convo.messages.length > 0) {
                const firstUserMsg = convo.messages.find(m => m.isUser);
                if (firstUserMsg) {
                    convo.name = firstUserMsg.text; // Use full text, don't truncate
                }
            }
        });

        // Convert to array, sort reverse-chrono, filter empty
        let sortedRooms = Object.values(conversations)
            .filter(room => room.messages.length > 0)
            .sort((a, b) => b.timestamp - a.timestamp);

        // Check availability for each room (async, but we'll do it in parallel)
        // For now, mark all as available - we'll check on-demand when sending
        // This avoids blocking the sync with slow AppleScript calls
        sortedRooms = sortedRooms.map(room => ({
            ...room,
            available: true  // Will be checked when actually sending
        }));

        const payload = JSON.stringify({
            type: "sync",
            rooms: sortedRooms
        });

        // Change detection
        const currentHash = crypto.createHash('md5').update(payload).digest('hex');
        
        if (currentHash === lastPayloadHash) {
            db.close();
            return;
        }
        
        lastPayloadHash = currentHash;
        console.log(`💬 ${sortedRooms.length} conversations`);

        // Broadcast to all clients
        let sentCount = 0;
        clients.forEach(client => {
            if (client.readyState === WebSocket.OPEN) {
                try {
                    client.send(payload);
                    sentCount++;
                } catch (err) {
                    console.error(`❌ Failed to send to client:`, err.message);
                }
            }
        });
        
        if (sentCount > 0) {
            console.log(`📤 Sent sync to ${sentCount} client(s) (${Math.round(payload.length / 1024)}KB)`);
        }

        db.close();
    });
}

// --- CHAT LOOKUP ---
function lookupChatName(composerId) {
    return new Promise((resolve) => {
        const db = new sqlite3.Database(DB_PATH, sqlite3.OPEN_READONLY, (err) => {
            if (err) {
                resolve(null);
                return;
            }
        });
        
        // Try composerData first for the chat name
        const query = `SELECT value FROM cursorDiskKV WHERE key = ?`;
        db.get(query, [`composerData:${composerId}`], (err, row) => {
            if (err || !row) {
                // Fallback: get first user message as name
                db.get(query, [`bubbleId:${composerId}:0`], (err2, bubbleRow) => {
                    db.close();
                    if (err2 || !bubbleRow) {
                        resolve(null);
                        return;
                    }
                    try {
                        const data = JSON.parse(bubbleRow.value);
                        if (data.type === 1 && data.text) {
                            resolve(data.text); // Use full text, don't truncate
                        } else {
                            resolve(null);
                        }
                    } catch (e) {
                        resolve(null);
                    }
                });
                return;
            }
            
            try {
                const data = JSON.parse(row.value);
                const name = data.name || data.text || null; // Use full name/text, don't truncate
                db.close();
                resolve(name);
            } catch (e) {
                db.close();
                resolve(null);
            }
        });
    });
}

// --- NEW CHAT HANDLING ---
async function handleNewChat(projectName, chatTitle, ws) {
    console.log(`🆕 New chat request received${projectName ? ` for project "${projectName}"` : ' (using active window)'}${chatTitle ? ` with title "${chatTitle}"` : ''}`);
    
    try {
        const result = await cursorAutomation.startNewChat(projectName || null, chatTitle || null);
        
        // Send acknowledgment
        const ack = {
            type: 'new_chat_ack',
            status: result.success ? 'started' : 'error',
            message: result.message,
            windowId: result.windowId,
            windowName: result.windowName,
            projectName: result.projectName,
            chatTitle: result.chatTitle
        };
        
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify(ack));
        }
        
        if (!result.success) {
            console.error(`❌ Failed to start new chat: ${result.message}`);
        } else {
            console.log(`✅ New chat started successfully in ${result.windowName || 'active window'}${result.chatTitle ? ` with title "${result.chatTitle}"` : ''}`);
        }
        
        return result;
    } catch (error) {
        console.error(`❌ Error starting new chat:`, error);
        const ack = {
            type: 'new_chat_ack',
            status: 'error',
            message: `Error: ${error.message || String(error)}`,
            windowId: null,
            windowName: null,
            projectName: projectName || null,
            chatTitle: chatTitle || null
        };
        
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify(ack));
        }
        
        return { success: false, message: error.message || String(error) };
    }
}

// --- FOLLOW-UP HANDLING VIA APPLESCRIPT ---
async function handleFollowUp(composerId, text, ws) {
    console.log(`📱 Follow-up received for ${composerId}: "${text.substring(0, 50)}..."`);
    
    try {
        // Step 1: Look up the chat name from DB
        const chatName = await lookupChatName(composerId);
        console.log(`📍 Chat name: ${chatName ? `"${chatName}"` : '(not found)'}`);
        if (chatName) {
            console.log(`   → Full length: ${chatName.length} characters`);
        }
        
        if (!chatName) {
            const errorMsg = 'Chat not found in database';
            console.error(`❌ ${errorMsg}`);
            const ack = {
                type: 'followup_ack',
                composerId: composerId,
                chatName: null,
                status: 'error',
                message: errorMsg
            };
            if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify(ack));
            }
            return { success: false, message: errorMsg };
        }
        
        // Step 2: Check if chat is accessible (window is open)
        console.log(`🔍 Checking if chat is accessible...`);
        const isAccessible = await cursorAutomation.isChatAccessible(chatName);
        
        if (!isAccessible) {
            const errorMsg = 'Chat window is closed. Please open the chat in Cursor to send messages.';
            console.error(`❌ ${errorMsg}`);
            const ack = {
                type: 'followup_ack',
                composerId: composerId,
                chatName: chatName,
                status: 'unavailable',
                message: errorMsg
            };
            if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify(ack));
            }
            return { success: false, message: errorMsg, unavailable: true };
        }
        
        // Step 3: Navigate to the chat (best effort)
        console.log(`📍 Navigating to chat...`);
        const navResult = await cursorAutomation.openChatByName(chatName);
        console.log(`📍 Navigation: ${navResult.message}`);
        
        // Check if navigation failed due to low confidence
        if (!navResult.success) {
            const errorMsg = navResult.message || 'Failed to find chat in any accessible window';
            console.error(`❌ ${errorMsg}`);
            const ack = {
                type: 'followup_ack',
                composerId: composerId,
                chatName: chatName,
                status: 'unavailable',
                message: errorMsg,
                confidence: navResult.confidence || 0
            };
            if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify(ack));
            }
            return { success: false, message: errorMsg, unavailable: true, confidence: navResult.confidence };
        }
        
        await new Promise(resolve => setTimeout(resolve, 500));
        
        // Step 4: Send the message
        const result = await cursorAutomation.sendMessageToCursor(text, {
            useClipboard: true,
            focusChat: false,  // Already focused during navigation
            skipActivation: true  // Don't activate - we're already in the correct window
        });
        
        // Send acknowledgment
        const ack = {
            type: 'followup_ack',
            composerId: composerId,
            chatName: chatName,
            status: result.success ? 'sent' : 'error',
            message: result.message,
            confidence: navResult.confidence || 1.0
        };
        
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify(ack));
        }
        
        if (!result.success) {
            console.error(`❌ Failed to send follow-up: ${result.message}`);
        }
        
        return result;
    } catch (error) {
        console.error(`❌ Error handling follow-up:`, error);
        const ack = {
            type: 'followup_ack',
            composerId: composerId,
            chatName: null,
            status: 'error',
            message: `Error: ${error.message || String(error)}`
        };
        
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify(ack));
        }
        
        return { success: false, message: error.message || String(error) };
    }
}

// --- MESSAGE HANDLING ---
async function handleMessage(ws, data) {
    try {
        const message = JSON.parse(data.toString());
        
        if (message.type === 'followup') {
            await handleFollowUp(message.composerId, message.text, ws);
        }
        
        if (message.type === 'new_chat') {
            await handleNewChat(message.projectName, message.chat_title, ws);
        }
        
        if (message.type === 'ping') {
            ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
        }
        
    } catch (e) {
        console.error("❌ Message parse error:", e.message);
    }
}

// --- CONNECTION HANDLING ---
wss.on('connection', (ws) => {
    clients.add(ws);
    console.log(`📱 Client connected (${clients.size} total)`);
    
    // Force send initial sync by temporarily bypassing hash check
    const savedHash = lastPayloadHash;
    lastPayloadHash = null;
    
    // Small delay to ensure WebSocket is fully ready
    setTimeout(() => {
        console.log(`📡 Sending initial sync to new client...`);
        pollCursorDB();
        // Restore hash after sending
        setTimeout(() => {
            lastPayloadHash = savedHash;
        }, 200);
    }, 100);
    
    ws.on('message', (data) => {
        console.log(`📥 Received message from client`);
        handleMessage(ws, data);
    });
    
    ws.on('close', () => {
        clients.delete(ws);
        console.log(`📱 Client disconnected (${clients.size} remaining)`);
    });
    
    ws.on('error', (err) => {
        console.error(`❌ WebSocket error:`, err.message);
    });
});

// Poll every 5 seconds
setInterval(pollCursorDB, 5000);

// Startup check
(async () => {
    const isRunning = await cursorAutomation.isCursorRunning();
    console.log(`🖥️  Cursor is ${isRunning ? 'running' : 'not running'}`);
    if (!isRunning) {
        console.log(`   ⚠️  Start Cursor to enable follow-up messages`);
    }
    
    // Check Accessibility permissions
    console.log(`🔐 Checking Accessibility permissions...`);
    try {
        const hasPermissions = await cursorAutomation.testAccessibilityPermissions();
        if (!hasPermissions) {
            console.log(`\n❌ Accessibility permissions NOT granted!`);
            console.log(`   Follow-up messages will fail until permissions are granted.`);
        } else {
            console.log(`✅ Accessibility permissions OK`);
        }
    } catch (error) {
        console.log(`⚠️  Could not verify Accessibility permissions: ${error.message}`);
    }
})();

console.log(`
📋 Protocol:
   Client → Bridge:  { type: "followup", composerId: "...", text: "..." }
   Client → Bridge:  { type: "new_chat", projectName: "...", chat_title: "..." }
   Bridge → Client:  { type: "sync", rooms: [...] }
   Bridge → Client:  { type: "followup_ack", chatName: "...", status: "sent|error" }
   Bridge → Client:  { type: "new_chat_ack", status: "started|error", windowId: <number|null>, windowName: "...", projectName: "...", chatTitle: "..." }
   
🔄 Flow:
   Follow-up:
   1. Look up chat name from DB using composerId
   2. Navigate to that chat via command palette (best effort)
   3. Send message via AppleScript
   
   New Chat:
   1. Find windows matching project name (or use active window if not specified)
   2. Activate the first matching window
   3. Focus chat panel (Cmd+L) to bring chat tab into focus
   4. Create new chat using Cmd+T keyboard shortcut
   5. If chat_title provided, send it as first message to name the chat
   
🔑 Requirements:
   - Cursor must be running
   - Terminal must have Accessibility permissions
     (System Preferences → Security & Privacy → Privacy → Accessibility)
`);
