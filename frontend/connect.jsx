import { connect } from "@argent/get-starknet";
import { Provider, Contract, uint256 } from "starknet";

const provider = new Provider({ nodeUrl: import.meta.env.VITE_STARKNET_RPC });

export async function connectWallet() {
  const starknet = await connect();
  await starknet?.enable({ showModal: true });
  return starknet!.account;
}

export async function rsvp(eventId: string, token: string, deposit: string) {
  const account = await connectWallet();
  const contract = new Contract(ABI_EVENT_RSVP, EVENT_RSVP_ADDRESS, account);

  // User must have already approved deposit to contract on the ERC20
  // Then:
  const tx = await contract.rsvp(eventId);
  await provider.waitForTransaction(tx.transaction_hash);
}

export async function submitProof(eventId: string) {
  const account = await connectWallet();
  const contract = new Contract(ABI_EVENT_RSVP, EVENT_RSVP_ADDRESS, account);
  const proofBytes = new TextEncoder().encode("OK"); // mock
  const tx = await contract.submit_attendance_proof(eventId, proofBytes);
  await provider.waitForTransaction(tx.transaction_hash);
}
