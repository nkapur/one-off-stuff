#!/usr/bin/env node

/**
 * Test script for Cursor automation
 * 
 * Usage:
 *   node test-automation.js          # Interactive test
 *   node test-automation.js "Hello"  # Send specific message
 */

const cursorAutomation = require('./cursorAutomation');

async function main() {
    const testMessage = process.argv[2] || 'Hello from iOS! This is a test message.';
    
    console.log('🧪 Cursor Automation Test');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    // Check if Cursor is running
    console.log('1️⃣  Checking if Cursor is running...');
    const isRunning = await cursorAutomation.isCursorRunning();
    console.log(`   ${isRunning ? '✅ Cursor is running' : '❌ Cursor is NOT running'}\n`);
    
    if (!isRunning) {
        console.log('⚠️  Please start Cursor and try again.');
        process.exit(1);
    }
    
    // Test sending a message
    console.log('2️⃣  Sending test message to Cursor chat...');
    console.log(`   Message: "${testMessage}"\n`);
    
    console.log('   ⏳ This will:');
    console.log('      - Activate Cursor');
    console.log('      - Focus the chat input (Cmd+L)');
    console.log('      - Paste the message');
    console.log('      - Press Enter to send\n');
    
    const result = await cursorAutomation.sendMessageToCursor(testMessage);
    
    if (result.success) {
        console.log(`\n✅ Success: ${result.message}`);
        console.log('\n📝 Check Cursor - the message should appear in the chat!');
    } else {
        console.log(`\n❌ Failed: ${result.message}`);
        console.log('\n🔧 Troubleshooting:');
        console.log('   1. Make sure Cursor is open and responsive');
        console.log('   2. Grant Accessibility permissions:');
        console.log('      System Preferences → Security & Privacy → Privacy → Accessibility');
        console.log('      Add: Terminal (or your terminal app)');
    }
    
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main().catch(err => {
    console.error('Test failed:', err);
    process.exit(1);
});
