const fs = require('fs');
const { ethers } = require('ethers');

// 1. ABIs
const EVENT_ABI = [
  "event MessageStored(bytes32 id, uint256 indexed nonce, address indexed caller, address indexed target, uint256 timestamp, bytes data)"
];

const FORWARD_ABI = [
  "function forwardMessage(uint256 nonce, address l2Sender, address target, bytes message)"
];

const WITHDRAW_ABI = [
  "function executeTokenWithdrawal(address receiver, uint256 amount)"
];

// 2. Interfaces
const eventIface = new ethers.Interface(EVENT_ABI);
const forwardIface = new ethers.Interface(FORWARD_ABI);
const withdrawIface = new ethers.Interface(WITHDRAW_ABI);

// 3. Known addresses
const known = {
  "0x9c52b2c4a89e2be37972d18da937cbad8aa8bd50": "TokenBridge",
  "0x87ead3e78ef9e26de92083b75a3b037ac2883e16": "l2Handler",
  "0xff2bd636b9fc89645c2d336eaade2e4abafe1ea5": "l1Forwarder"
};

function label(addr) {
  const lower = addr.toLowerCase();
  return known[lower] ? `${addr} (${known[lower]})` : addr;
}

// 4. Load log data
const logs = JSON.parse(fs.readFileSync('./withdrawals.json', 'utf-8'));

// 5. Decode each log
logs.forEach((log, i) => {
  try {
    console.log(`\n🔹 Log #${i}`);

    // Step 1: Decode MessageStored event
    const parsedEvent = eventIface.parseLog(log);
    const data = parsedEvent.args.data;

    console.log(`  📦 MessageStored`);
    console.log(`    ID:         ${parsedEvent.args.id}`);
    console.log(`    Nonce:      ${parsedEvent.args.nonce.toString()}`);
    console.log(`    Caller:     ${label(parsedEvent.args.caller)}`);
    console.log(`    Target:     ${label(parsedEvent.args.target)}`);
    console.log(`    Timestamp:  ${parsedEvent.args.timestamp.toString()}`);

    // Step 2: Decode forwardMessage calldata
    const parsedForward = forwardIface.decodeFunctionData("forwardMessage", data);
    console.log(`  🚀 forwardMessage()`);
    console.log(`    Nonce:      ${parsedForward.nonce.toString()}`);
    console.log(`    L2 Sender:  ${label(parsedForward.l2Sender)}`);
    console.log(`    Target:     ${label(parsedForward.target)}`);

    // Step 3: Decode nested executeTokenWithdrawal() calldata
    const parsedWithdraw = withdrawIface.decodeFunctionData("executeTokenWithdrawal", parsedForward.message);
    console.log(`  💸 executeTokenWithdrawal()`);
    console.log(`    Receiver:   ${label(parsedWithdraw.receiver)}`);
    console.log(`    Amount:     ${ethers.formatEther(parsedWithdraw.amount)} ETH`);

  } catch (err) {
    console.error(`❌ Failed to decode log #${i}: ${err.message}`);
  }
});
