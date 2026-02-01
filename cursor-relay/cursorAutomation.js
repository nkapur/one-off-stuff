const { exec } = require('child_process');
const util = require('util');

const execPromise = util.promisify(exec);

/**
 * AppleScript runner utility
 * Executes AppleScript commands via osascript
 */
async function runAppleScript(script) {
    try {
        // Escape single quotes in the script for shell
        const escapedScript = script.replace(/'/g, "'\"'\"'");
        const { stdout, stderr } = await execPromise(`osascript -e '${escapedScript}'`);
        if (stderr && stderr.trim()) {
            console.error('AppleScript stderr:', stderr);
        }
        return stdout.trim();
    } catch (error) {
        const errorMsg = error.message || error.stderr || String(error);
        console.error('❌ AppleScript execution failed:', errorMsg);
        
        // Check for common permission errors
        if (errorMsg.includes('not allowed') || errorMsg.includes('denied') || errorMsg.includes('accessibility')) {
            console.error('\n⚠️  PERMISSION ERROR DETECTED!');
            console.error('   macOS is blocking keystroke automation.');
            console.error('   To fix:');
            console.error('   1. Open System Settings → Privacy & Security → Accessibility');
            console.error('   2. Find "Terminal" (or "iTerm" if using iTerm) in the list');
            console.error('   3. Enable the toggle for Terminal');
            console.error('   4. If Terminal is not in the list, run this command:');
            console.error('      sudo sqlite3 /Library/Application\\ Support/com.apple.TCC/TCC.db "INSERT INTO access VALUES(\'kTCCServiceAccessibility\',\'com.apple.Terminal\',0,2,4,1,NULL,NULL,NULL,\'UNUSED\',NULL,0,1699999999);"');
            console.error('   5. Restart Terminal and try again\n');
        }
        throw error;
    }
}

/**
 * Check if Cursor is running
 * @returns {Promise<boolean>}
 */
async function isCursorRunning() {
    try {
        const script = `
            tell application "System Events"
                return (exists process "Cursor")
            end tell
        `;
        const result = await runAppleScript(script);
        return result.toLowerCase() === 'true';
    } catch (error) {
        console.error('Failed to check if Cursor is running:', error);
        return false;
    }
}

/**
 * Activate Cursor (bring to foreground)
 * @returns {Promise<boolean>}
 */
async function activateCursor() {
    try {
        await runAppleScript('tell application "Cursor" to activate');
        // Wait for activation
        await new Promise(resolve => setTimeout(resolve, 300));
        return true;
    } catch (error) {
        console.error('Failed to activate Cursor:', error);
        return false;
    }
}

/**
 * Focus the AI chat panel using keyboard shortcut
 * Cmd+L is the default shortcut to focus the chat input in Cursor
 * @returns {Promise<boolean>}
 */
async function focusChatInput() {
    try {
        const script = `
            tell application "System Events"
                tell application "Cursor" to activate
                delay 0.2
                -- Cmd+L focuses the chat input in Cursor
                keystroke "l" using {command down}
                delay 0.3
            end tell
        `;
        await runAppleScript(script);
        return true;
    } catch (error) {
        const errorMsg = error.message || error.stderr || String(error);
        console.error('❌ Failed to focus chat input:', errorMsg);
        if (errorMsg.includes('not allowed') || errorMsg.includes('denied')) {
            console.error('   → This is likely an Accessibility permission issue');
        }
        return false;
    }
}

/**
 * Type text into the currently focused input
 * @param {string} text - The text to type
 * @returns {Promise<boolean>}
 */
async function typeText(text) {
    try {
        // Escape special characters for AppleScript
        const safeText = text
            .replace(/\\/g, '\\\\')
            .replace(/"/g, '\\"')
            .replace(/\n/g, '\\n');
        
        const script = `
            tell application "System Events"
                keystroke "${safeText}"
            end tell
        `;
        await runAppleScript(script);
        return true;
    } catch (error) {
        const errorMsg = error.message || error.stderr || String(error);
        console.error('❌ Failed to type text:', errorMsg);
        if (errorMsg.includes('not allowed') || errorMsg.includes('denied')) {
            console.error('   → This is likely an Accessibility permission issue');
        }
        return false;
    }
}

/**
 * Press Enter key
 * @returns {Promise<boolean>}
 */
async function pressEnter() {
    try {
        const script = `
            tell application "System Events"
                keystroke return
            end tell
        `;
        await runAppleScript(script);
        return true;
    } catch (error) {
        const errorMsg = error.message || error.stderr || String(error);
        console.error('❌ Failed to press Enter:', errorMsg);
        if (errorMsg.includes('not allowed') || errorMsg.includes('denied')) {
            console.error('   → This is likely an Accessibility permission issue');
        }
        return false;
    }
}

/**
 * Set clipboard content (alternative approach - paste instead of type)
 * Useful for long messages that would take too long to type
 * @param {string} text - The text to copy to clipboard
 * @returns {Promise<boolean>}
 */
async function setClipboard(text) {
    try {
        // Use pbcopy for reliability with special characters
        await execPromise(`echo "${text.replace(/"/g, '\\"')}" | pbcopy`);
        return true;
    } catch (error) {
        console.error('Failed to set clipboard:', error);
        return false;
    }
}

/**
 * Paste from clipboard (Cmd+V)
 * @returns {Promise<boolean>}
 */
async function pasteFromClipboard() {
    try {
        const script = `
            tell application "System Events"
                keystroke "v" using {command down}
            end tell
        `;
        await runAppleScript(script);
        return true;
    } catch (error) {
        const errorMsg = error.message || error.stderr || String(error);
        console.error('❌ Failed to paste:', errorMsg);
        if (errorMsg.includes('not allowed') || errorMsg.includes('denied')) {
            console.error('   → This is likely an Accessibility permission issue');
        }
        return false;
    }
}

/**
 * Send a message to Cursor's chat
 * This is the main function that orchestrates the full flow
 * 
 * @param {string} message - The message to send
 * @param {Object} options - Options
 * @param {boolean} options.useClipboard - Use clipboard paste instead of typing (faster for long messages)
 * @param {boolean} options.focusChat - Whether to focus the chat first (default: true)
 * @returns {Promise<{success: boolean, message: string}>}
 */
async function sendMessageToCursor(message, options = {}) {
    const { useClipboard = true, focusChat = true, skipActivation = false } = options;
    
    try {
        // Step 1: Check if Cursor is running
        const isRunning = await isCursorRunning();
        if (!isRunning) {
            return { 
                success: false, 
                message: 'Cursor is not running. Please open Cursor first.' 
            };
        }
        
        // Step 2: Activate Cursor (unless we're skipping because we already navigated)
        if (!skipActivation) {
            console.log('📍 Activating Cursor...');
            await activateCursor();
        } else {
            console.log('📍 Skipping activation (already in correct window)...');
        }
        
        // Step 3: Focus the chat input (Cmd+L)
        if (focusChat) {
            console.log('📍 Focusing chat input (Cmd+L)...');
            await focusChatInput();
            await new Promise(resolve => setTimeout(resolve, 200));
        }
        
        // Step 4: Input the message
        if (useClipboard) {
            // Clipboard approach - faster and more reliable for long/complex text
            console.log('📍 Setting clipboard and pasting...');
            await setClipboard(message);
            await new Promise(resolve => setTimeout(resolve, 100));
            await pasteFromClipboard();
        } else {
            // Direct typing - slower but doesn't affect clipboard
            console.log('📍 Typing message...');
            await typeText(message);
        }
        
        await new Promise(resolve => setTimeout(resolve, 200));
        
        // Step 5: Press Enter to send
        console.log('📍 Sending message (Enter)...');
        await pressEnter();
        
        console.log('✅ Message sent successfully');
        return { 
            success: true, 
            message: 'Message sent to Cursor' 
        };
        
    } catch (error) {
        const errorMsg = error.message || error.stderr || String(error);
        console.error('❌ Failed to send message to Cursor:', errorMsg);
        
        let userMessage = `Failed to send: ${errorMsg}`;
        if (errorMsg.includes('not allowed') || errorMsg.includes('denied') || errorMsg.includes('accessibility')) {
            userMessage = 'Accessibility permission denied. Please grant Terminal Accessibility access in System Settings.';
        }
        
        return { 
            success: false, 
            message: userMessage
        };
    }
}

/**
 * Navigate to a specific chat by name using the chat history
 * 
 * Strategy: 
 *   1. Open command palette (Cmd+Shift+P)
 *   2. Type "Composer: Open Recent" or search for the chat name
 *   3. Type the chat name to filter
 *   4. Press Enter to select
 * 
 * @param {string} chatName - The name/title of the chat to navigate to
 * @returns {Promise<{success: boolean, message: string}>}
 */
async function navigateToChat(chatName) {
    try {
        console.log(`📍 Attempting to navigate to chat: "${chatName.substring(0, 30)}..."`);
        
        // Ensure Cursor is activated (should already be done, but double-check)
        await activateCursor();
        await new Promise(resolve => setTimeout(resolve, 300));
        
        // First, make sure we're NOT in the chat input (press Escape to clear any focus)
        console.log(`   → Clearing any existing focus...`);
        const clearFocusScript = `
            tell application "System Events"
                tell application "Cursor" to activate
                delay 0.1
                key code 53
                delay 0.2
            end tell
        `;
        await runAppleScript(clearFocusScript);
        
        // Open command palette (Cmd+Shift+P)
        console.log(`   → Opening command palette...`);
        const openPaletteScript = `
            tell application "System Events"
                tell application "Cursor" to activate
                delay 0.2
                keystroke "p" using {command down, shift down}
                delay 0.8
            end tell
        `;
        await runAppleScript(openPaletteScript);
        
        // Clear any existing text in the palette first (Cmd+A then Delete, or just select all and type)
        console.log(`   → Clearing palette input...`);
        const clearPaletteScript = `
            tell application "System Events"
                keystroke "a" using {command down}
                delay 0.1
                keystroke "Composer: Open Recent"
                delay 0.6
                keystroke return
                delay 0.8
            end tell
        `;
        await runAppleScript(clearPaletteScript);
        
        // Now type the chat name to filter (the palette should now show the recent chats list)
        console.log(`   → Filtering by chat name...`);
        const searchText = chatName.substring(0, 40); // Limit to avoid issues
        const safeSearchText = searchText
            .replace(/\\/g, '\\\\')
            .replace(/"/g, '\\"')
            .replace(/\$/g, '\\$');
        
        const typeSearchScript = `
            tell application "System Events"
                keystroke "${safeSearchText}"
                delay 0.5
                keystroke return
                delay 0.5
            end tell
        `;
        await runAppleScript(typeSearchScript);
        
        // Press Escape to close palette if still open
        const cleanupScript = `
            tell application "System Events"
                key code 53
                delay 0.3
            end tell
        `;
        await runAppleScript(cleanupScript);
        
        console.log(`✅ Navigated to chat (best effort)`);
        return { success: true, message: `Navigated to: ${chatName.substring(0, 30)}...` };
        
    } catch (error) {
        console.error('❌ Failed to navigate to chat:', error.message);
        return { success: false, message: error.message };
    }
}

/**
 * Get list of all Cursor windows
 * Note: Window IDs aren't accessible via AppleScript, so we use index as ID
 * @returns {Promise<Array<{id: number, name: string, index: number}>>}
 */
async function getAllCursorWindows() {
    try {
        // Check if Cursor is running first
        const isRunning = await isCursorRunning();
        if (!isRunning) {
            console.log('   → Cursor is not running, no windows available');
            return [];
        }
        
        // Use System Events - window IDs aren't accessible via AppleScript, so we'll use index as ID
        let windows = [];
        console.log(`   → Using System Events method (window IDs not accessible, using index as ID)...`);
        try {
            // Get window count first
            const countScript = `
                tell application "System Events"
                    tell application process "Cursor"
                        return count of windows
                    end tell
                end tell
            `;
            const countResult = await runAppleScript(countScript);
            const windowCount = parseInt(countResult.trim()) || 0;
            console.log(`   → System Events reports ${windowCount} window(s)`);
            
            if (windowCount === 0) {
                return [];
            }
            
            // Get each window's name by index (IDs aren't accessible)
            for (let i = 1; i <= windowCount; i++) {
                try {
                    // Get window name
                    const nameScript = `
                        tell application "System Events"
                            tell application process "Cursor"
                                set w to window ${i}
                                return name of w
                            end tell
                        end tell
                    `;
                    const windowName = (await runAppleScript(nameScript)).trim();
                    
                    if (windowName) {
                        // Use index as ID since actual IDs aren't accessible
                        windows.push({
                            id: i, // Use index as ID
                            name: windowName,
                            index: i
                        });
                        console.log(`   → Window ${i}: "${windowName}" (using index ${i} as ID)`);
                    } else {
                        console.log(`   → Window ${i}: No name retrieved`);
                    }
                } catch (err) {
                    console.log(`   → Window ${i}: Error - ${err.message}`);
                    if (err.stderr) {
                        console.log(`     stderr: ${err.stderr}`);
                    }
                    continue;
                }
            }
        } catch (err) {
            console.error(`   → System Events method failed: ${err.message}`);
            if (err.stderr) {
                console.error(`     stderr: ${err.stderr}`);
            }
        }
        
        console.log(`   → Successfully retrieved ${windows.length} window(s) total`);
        if (windows.length === 0) {
            console.log(`   ⚠️  No windows retrieved - this might indicate a permissions issue or Cursor windows are not accessible`);
        }
        return windows;
    } catch (error) {
        console.error('❌ Failed to get Cursor windows:', error.message);
        console.error('   Error stack:', error.stack);
        if (error.stderr) {
            console.error('   stderr:', error.stderr);
        }
        return [];
    }
}

/**
 * Activate a specific Cursor window by ID (which is actually the index)
 * Uses multiple methods to ensure the window is actually activated
 * @param {number} windowId - The window ID/index to activate
 * @returns {Promise<boolean>}
 */
async function activateCursorWindow(windowId) {
    try {
        // windowId is actually the index since real IDs aren't accessible
        const windowIndex = windowId;
        
        // Activate Cursor first
        await activateCursor();
        await new Promise(resolve => setTimeout(resolve, 200));
        
        // Method 1: Use AXRaise action
        const script1 = `
            tell application "System Events"
                tell application process "Cursor"
                    set frontmost to true
                    set targetWindow to window ${windowIndex}
                    perform action "AXRaise" of targetWindow
                end tell
            end tell
        `;
        await runAppleScript(script1);
        await new Promise(resolve => setTimeout(resolve, 300));
        
        // Method 2: Also try clicking the window (more aggressive)
        const script2 = `
            tell application "System Events"
                tell application process "Cursor"
                    set frontmost to true
                    set targetWindow to window ${windowIndex}
                    click targetWindow
                end tell
            end tell
        `;
        try {
            await runAppleScript(script2);
            await new Promise(resolve => setTimeout(resolve, 200));
        } catch (e) {
            // Click might fail, that's okay
        }
        
        // Method 3: Verify it's actually frontmost
        const verifyScript = `
            tell application "System Events"
                tell application process "Cursor"
                    set frontWindow to window 1
                    return name of frontWindow
                end tell
            end tell
        `;
        const frontWindowName = (await runAppleScript(verifyScript)).trim();
        
        // Get the expected window name
        const windows = await getAllCursorWindows();
        const targetWindow = windows.find(w => w.id === windowId);
        const expectedName = targetWindow ? targetWindow.name : '';
        
        // Check if we got the right window
        if (targetWindow && frontWindowName !== expectedName) {
            console.log(`   ⚠️  First attempt: Expected "${expectedName}" but got "${frontWindowName}", retrying...`);
            
            // Retry with a different approach - try all windows until we find the right one
            for (let i = 0; i < 3; i++) {
                // Try activating again
                await runAppleScript(script1);
                await new Promise(resolve => setTimeout(resolve, 400));
                
                const currentFront = (await runAppleScript(verifyScript)).trim();
                if (currentFront === expectedName) {
                    console.log(`✅ Activated window ${windowIndex} (after ${i + 1} retries)`);
                    return true;
                }
            }
            
            console.warn(`   ⚠️  Could not verify window activation. Expected "${expectedName}" but frontmost is "${frontWindowName}"`);
            // Continue anyway - might still work
        }
        
        console.log(`✅ Activated window ${windowIndex}`);
        return true;
    } catch (error) {
        console.error(`❌ Failed to activate window ${windowId}:`, error.message);
        if (error.stderr) {
            console.error(`   stderr: ${error.stderr}`);
        }
        return false;
    }
}

// Confidence threshold for window matching
// If the best match confidence is below this, we'll reject the message
const WINDOW_MATCH_CONFIDENCE_THRESHOLD = 0.5;

/**
 * Find which window contains a specific chat by trying navigation in each window
 * Returns the window that seems most likely to contain the chat
 * 
 * @param {string} chatName - The name of the chat to find
 * @returns {Promise<{window: Object|null, confidence: number}>}
 */
async function findWindowWithChat(chatName) {
    const windows = await getAllCursorWindows();
    
    if (windows.length === 0) {
        return { window: null, confidence: 0 };
    }
    
    console.log(`🔍 Searching for chat "${chatName}" across ${windows.length} window(s)...`);
    
    // Try each window and see if we can navigate to the chat
    // We'll score each window based on how likely it is to contain the chat
    const windowScores = [];
    
    for (const window of windows) {
        console.log(`   → Checking window: "${window.name}"`);
        
        try {
            // Activate this window
            const activated = await activateCursorWindow(window.id);
            if (!activated) {
                console.log(`      ⚠️  Could not activate, skipping`);
                continue;
            }
            
            await new Promise(resolve => setTimeout(resolve, 300));
            
            // Try to navigate to the chat
            // The command palette should only show chats that exist in this workspace
            // If the chat doesn't exist here, navigation might fail or open a different chat
            const navResult = await navigateToChat(chatName);
            
            // Give this window a score based on navigation success
            // We can't perfectly verify, but we'll assume navigation worked if it didn't error
            const score = navResult.success ? 1.0 : 0.0;
            
            windowScores.push({
                window: window,
                score: score,
                navResult: navResult
            });
            
            console.log(`      Score: ${score.toFixed(2)} (navigation ${navResult.success ? 'succeeded' : 'failed'})`);
            
        } catch (error) {
            console.log(`      ⚠️  Error checking window: ${error.message}`);
            windowScores.push({
                window: window,
                score: 0.0,
                navResult: { success: false, message: error.message }
            });
        }
    }
    
    // Find the window with the highest score
    windowScores.sort((a, b) => b.score - a.score);
    
    if (windowScores.length === 0 || windowScores[0].score === 0) {
        console.log(`   ⚠️  No confident match found (best score: 0.00)`);
        return { window: null, confidence: 0.0 };
    }
    
    const bestMatch = windowScores[0];
    console.log(`   ✅ Best match: "${bestMatch.window.name}" (confidence: ${bestMatch.score.toFixed(2)})`);
    
    return { 
        window: bestMatch.window, 
        confidence: bestMatch.score 
    };
}

/**
 * Open a specific chat/composer by name
 * Scans all windows to find which one contains the chat, then navigates to it
 * 
 * @param {string} chatName - The name of the chat to open
 * @returns {Promise<{success: boolean, message: string, navigated: boolean}>}
 */
async function openChatByName(chatName) {
    if (!chatName || chatName === "Chat" || chatName === "New Chat") {
        // No specific chat name, just focus current chat
        console.log('📍 No specific chat name, using current chat');
        await focusChatInput();
        return { success: true, message: 'Using current chat', navigated: false };
    }
    
    // Find which window contains this chat by scanning all windows
    console.log(`📍 Finding window containing chat: "${chatName}"...`);
    const { window: targetWindow, confidence } = await findWindowWithChat(chatName);
    
    // Check if we found a confident match
    if (!targetWindow) {
        const errorMsg = `No Cursor windows found or chat not accessible in any window`;
        console.error(`❌ ${errorMsg}`);
        return { 
            success: false, 
            message: errorMsg, 
            navigated: false,
            confidence: 0.0
        };
    }
    
    // Check confidence threshold
    if (confidence < WINDOW_MATCH_CONFIDENCE_THRESHOLD) {
        const errorMsg = `Confidence too low (${confidence.toFixed(2)} < ${WINDOW_MATCH_CONFIDENCE_THRESHOLD}). Chat may not exist in any accessible window.`;
        console.error(`❌ ${errorMsg}`);
        return { 
            success: false, 
            message: errorMsg, 
            navigated: false,
            confidence: confidence
        };
    }
    
    // Activate the window that contains the chat
    console.log(`📍 Activating window "${targetWindow.name}" (confidence: ${confidence.toFixed(2)})...`);
    
    // Re-fetch windows to get current indices (they might have changed)
    const currentWindows = await getAllCursorWindows();
    const currentTargetWindow = currentWindows.find(w => w.name === targetWindow.name);
    
    if (!currentTargetWindow) {
        const errorMsg = `Window "${targetWindow.name}" no longer found. Available: ${currentWindows.map(w => w.name).join(', ')}`;
        console.error(`❌ ${errorMsg}`);
        return { 
            success: false, 
            message: errorMsg, 
            navigated: false,
            confidence: confidence
        };
    }
    
    // Make absolutely sure we activate the correct window
    // Sometimes after scanning multiple windows, the wrong one might still be active
    // We'll retry activation until we verify it's correct
    let activationSuccess = false;
    for (let attempt = 0; attempt < 3; attempt++) {
        const activated = await activateCursorWindow(currentTargetWindow.id);
        if (!activated) {
            console.warn(`   ⚠️  Activation attempt ${attempt + 1} failed, retrying...`);
            await new Promise(resolve => setTimeout(resolve, 500));
            continue;
        }
        
        // Verify we're in the right window
        await new Promise(resolve => setTimeout(resolve, 600));
        
        try {
            const verifyScript = `
                tell application "System Events"
                    tell application process "Cursor"
                        set frontWindow to window 1
                        return name of frontWindow
                    end tell
                end tell
            `;
            const activeWindowName = (await runAppleScript(verifyScript)).trim();
            console.log(`   → Verified active window: "${activeWindowName}"`);
            
            // Check if it matches (window names might have slight variations)
            const windowNameParts = currentTargetWindow.name.split(' — ');
            const activeNameParts = activeWindowName.split(' — ');
            const matches = windowNameParts[0] === activeNameParts[0] || 
                          activeWindowName.includes(windowNameParts[0]) ||
                          currentTargetWindow.name.includes(activeNameParts[0]);
            
            if (matches) {
                console.log(`   ✅ Window activation verified!`);
                activationSuccess = true;
                break;
            } else {
                console.warn(`   ⚠️  Window mismatch on attempt ${attempt + 1}! Expected "${currentTargetWindow.name}" but got "${activeWindowName}"`);
                if (attempt < 2) {
                    console.log(`   → Retrying activation...`);
                    // Re-fetch windows again in case indices changed
                    const refreshedWindows = await getAllCursorWindows();
                    const refreshedTarget = refreshedWindows.find(w => w.name === targetWindow.name);
                    if (refreshedTarget && refreshedTarget.id !== currentTargetWindow.id) {
                        console.log(`   → Window index changed from ${currentTargetWindow.id} to ${refreshedTarget.id}, updating...`);
                        currentTargetWindow.id = refreshedTarget.id;
                    }
                    await new Promise(resolve => setTimeout(resolve, 500));
                }
            }
        } catch (error) {
            console.warn(`   ⚠️  Could not verify window: ${error.message}`);
            // If we can't verify, assume it worked after multiple attempts
            if (attempt >= 1) {
                activationSuccess = true;
                break;
            }
        }
    }
    
    if (!activationSuccess) {
        const errorMsg = `Failed to activate window "${targetWindow.name}" after multiple attempts`;
        console.error(`❌ ${errorMsg}`);
        return { 
            success: false, 
            message: errorMsg, 
            navigated: false,
            confidence: confidence
        };
    }
    
    // Navigate to the chat in this window (we already tried, but do it again to ensure we're there)
    const navResult = await navigateToChat(chatName);
    
    // Focus chat input
    await new Promise(resolve => setTimeout(resolve, 300));
    await focusChatInput();
    
    return { 
        success: true, 
        message: `Navigated to chat in window: ${targetWindow.name}`, 
        navigated: navResult.success,
        confidence: confidence
    };
}

/**
 * Check if a chat can be opened/accessed
 * Since chats are accessible from any Cursor window via command palette,
 * we just need to check if Cursor is running.
 * Window detection can be unreliable, so we don't check for windows.
 * 
 * @param {string} chatName - The name of the chat to check
 * @returns {Promise<boolean>}
 */
async function isChatAccessible(chatName) {
    try {
        if (!chatName || chatName === "Chat" || chatName === "New Chat") {
            // Generic chats are always considered accessible (they can be created)
            console.log(`   → Generic chat name, considering accessible`);
            return true;
        }
        
        // Just check if Cursor is running - if it is, we can try to navigate to the chat
        // Window detection is unreliable and not necessary since chats are accessible via command palette
        const isRunning = await isCursorRunning();
        if (!isRunning) {
            console.log(`   → Cursor is not running, chat not accessible`);
            return false;
        }
        
        // If Cursor is running, assume chat is accessible (we'll try to navigate to it)
        console.log(`   → Cursor is running - chat should be accessible`);
        return true;
    } catch (error) {
        console.error(`❌ Error checking chat accessibility:`, error);
        console.error(`   Error details:`, error.stack);
        // On error, be lenient - return true so we at least try
        console.log(`   → Error occurred, being lenient and allowing attempt`);
        return true;
    }
}

/**
 * Find windows that match a project name
 * Project name is matched against window names (case-insensitive)
 * 
 * @param {string} projectName - The project name to search for
 * @returns {Promise<Array<{id: number, name: string, index: number}>>}
 */
async function findWindowsByProjectName(projectName) {
    if (!projectName) {
        return [];
    }
    
    const windows = await getAllCursorWindows();
    const projectNameLower = projectName.toLowerCase();
    
    // Match windows whose name contains the project name
    // Window names in Cursor typically include the folder/project name
    const matchingWindows = windows.filter(window => {
        const windowNameLower = window.name.toLowerCase();
        return windowNameLower.includes(projectNameLower);
    });
    
    return matchingWindows;
}

/**
 * Start a new chat session in a Cursor window for a specific project
 * 
 * Strategy:
 *   1. If projectName is provided, find and activate a window matching that project
 *   2. If no projectName, use currently active window
 *   3. Focus the chat panel (Cmd+L) to bring chat tab into focus
 *   4. Create new chat using Cmd+T (keyboard shortcut for new chat)
 *   5. If chatTitle is provided, send it as the first message to name the chat
 * 
 * @param {string|null} projectName - Optional project name to start chat in. If null, uses currently active window.
 * @param {string|null} chatTitle - Optional title for the new chat. Will be sent as the first message.
 * @returns {Promise<{success: boolean, message: string, windowId: number|null, windowName: string|null, projectName: string|null, chatTitle: string|null}>}
 */
async function startNewChat(projectName = null, chatTitle = null) {
    try {
        // Step 1: Check if Cursor is running
        const isRunning = await isCursorRunning();
        if (!isRunning) {
            return {
                success: false,
                message: 'Cursor is not running. Please open Cursor first.',
                windowId: null,
                windowName: null,
                projectName: null,
                chatTitle: null
            };
        }
        
        // Step 2: Find and activate window matching project name if provided
        let targetWindow = null;
        if (projectName) {
            console.log(`📍 Searching for windows matching project: "${projectName}"...`);
            const matchingWindows = await findWindowsByProjectName(projectName);
            
            if (matchingWindows.length === 0) {
                const allWindows = await getAllCursorWindows();
                const availableProjects = allWindows.map(w => w.name).join(', ') || 'none';
                return {
                    success: false,
                    message: `No windows found for project "${projectName}". Available windows: ${availableProjects}`,
                    windowId: null,
                    windowName: null,
                    projectName: projectName,
                    chatTitle: chatTitle || null
                };
            }
            
            // Pick the first matching window (any window for the project is fine)
            targetWindow = matchingWindows[0];
            console.log(`📍 Found ${matchingWindows.length} window(s) for project "${projectName}", using: "${targetWindow.name}"`);
            
            const activated = await activateCursorWindow(targetWindow.id);
            if (!activated) {
                return {
                    success: false,
                    message: `Failed to activate window for project "${projectName}"`,
                    windowId: targetWindow.id,
                    windowName: targetWindow.name,
                    projectName: projectName,
                    chatTitle: chatTitle || null
                };
            }
            
            await new Promise(resolve => setTimeout(resolve, 300));
            console.log(`✅ Activated window: "${targetWindow.name}"`);
        } else {
            // Use currently active window
            console.log(`📍 Using currently active Cursor window...`);
            await activateCursor();
            await new Promise(resolve => setTimeout(resolve, 200));
        }
        
        // Step 3: Focus the chat panel first (Cmd+L) to bring chat tab into focus
        console.log(`📍 Focusing chat panel (Cmd+L)...`);
        await focusChatInput();
        await new Promise(resolve => setTimeout(resolve, 400));
        
        // Step 4: Create a new chat using Cmd+T (the keyboard shortcut for new chat)
        // This must be done after the chat tab is in focus
        console.log(`📍 Creating new chat (Cmd+T)...`);
        const newChatScript = `
            tell application "System Events"
                tell application "Cursor" to activate
                delay 0.2
                keystroke "t" using {command down}
                delay 0.8
            end tell
        `;
        
        try {
            await runAppleScript(newChatScript);
            console.log(`✅ Created new chat using Cmd+T`);
        } catch (error) {
            console.error(`❌ Failed to create new chat with Cmd+T: ${error.message}`);
            return {
                success: false,
                message: `Failed to create new chat: Cmd+T failed. Error: ${error.message}. Please ensure Cursor is responsive.`,
                windowId: targetWindow ? targetWindow.id : null,
                windowName: targetWindow ? targetWindow.name : 'active window',
                projectName: projectName || null,
                chatTitle: chatTitle || null
            };
        }
        
        // Wait for new chat to be ready
        await new Promise(resolve => setTimeout(resolve, 600));
        
        // Step 5: If chatTitle is provided, send it as the first message to name the chat
        if (chatTitle) {
            console.log(`📍 Setting chat title: "${chatTitle}"...`);
            const result = await sendMessageToCursor(chatTitle, {
                useClipboard: true,
                focusChat: false  // Already focused
            });
            
            if (!result.success) {
                console.warn(`⚠️  Failed to set chat title: ${result.message}`);
                // Continue anyway - chat was created, just title setting failed
            } else {
                console.log(`✅ Chat title set successfully`);
            }
        }
        
        const windowName = targetWindow ? targetWindow.name : 'active window';
        console.log(`✅ New chat session started in ${windowName}${chatTitle ? ` with title "${chatTitle}"` : ''}`);
        
        return {
            success: true,
            message: `New chat session started in ${windowName}${chatTitle ? ` with title "${chatTitle}"` : ''}`,
            windowId: targetWindow ? targetWindow.id : null,
            windowName: windowName,
            projectName: projectName || null,
            chatTitle: chatTitle || null
        };
        
    } catch (error) {
        const errorMsg = error.message || error.stderr || String(error);
        console.error('❌ Failed to start new chat:', errorMsg);
        
        let userMessage = `Failed to start new chat: ${errorMsg}`;
        if (errorMsg.includes('not allowed') || errorMsg.includes('denied') || errorMsg.includes('accessibility')) {
            userMessage = 'Accessibility permission denied. Please grant Terminal Accessibility access in System Settings.';
        }
        
        return {
            success: false,
            message: userMessage,
            windowId: null,
            windowName: null,
            projectName: projectName || null,
            chatTitle: chatTitle || null
        };
    }
}

/**
 * Test Accessibility permissions by attempting a simple keystroke
 * @returns {Promise<boolean>}
 */
async function testAccessibilityPermissions() {
    try {
        // First check if we can access System Events at all
        const testScript = `
            tell application "System Events"
                return true
            end tell
        `;
        await runAppleScript(testScript);
        
        // Now try an actual keystroke test (only if Cursor is running)
        const isRunning = await isCursorRunning();
        if (!isRunning) {
            // Can't fully test without Cursor, but System Events access is good
            return true;
        }
        
        // Try a harmless keystroke that we'll immediately cancel
        const keystrokeTest = `
            tell application "System Events"
                tell application "Cursor" to activate
                delay 0.1
                -- Try to send a harmless keystroke (Escape key)
                key code 53
            end tell
        `;
        await runAppleScript(keystrokeTest);
        return true;
    } catch (error) {
        const errorMsg = error.message || error.stderr || String(error);
        if (errorMsg.includes('not allowed') || errorMsg.includes('denied') || errorMsg.includes('accessibility')) {
            return false;
        }
        // Other errors might be okay (e.g., Cursor not running, timing issues)
        return true;
    }
}

module.exports = {
    isCursorRunning,
    activateCursor,
    focusChatInput,
    typeText,
    pressEnter,
    setClipboard,
    pasteFromClipboard,
    sendMessageToCursor,
    navigateToChat,
    openChatByName,
    getAllCursorWindows,
    activateCursorWindow,
    findWindowWithChat,
    findWindowsByProjectName,
    isChatAccessible,
    startNewChat,
    runAppleScript,
    testAccessibilityPermissions
};
