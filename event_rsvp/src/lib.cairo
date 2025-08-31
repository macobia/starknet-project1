// event_rsvp/src/event_rsvp.cairo
// %lang starknet

use starknet::ContractAddress;
use starknet::get_caller_address;
use starknet::class_hash::ClassHash;
use starknet::storage::LegacyMap;

use starknet::syscalls::deploy_syscall;
use starknet::syscalls::call_contract_syscall;
use starknet::testing::events::emit_event;
use starknet::math::uint128;

use core::option::Option;
use core::traits::Into;
use core::array::ArrayTrait;

#[derive(Copy, Drop, Serde, PartialEq)]
struct Event {
    organizer: ContractAddress,
    token: ContractAddress,       // ERC20 token used for deposits
    deposit_amount: u128,
    attendee_count: u32,
    finalized: bool
}

#[storage]
struct Storage {
    next_event_id: u128,
    events: LegacyMap<u128, Event>,
    attending: LegacyMap<(u128, ContractAddress), bool>,
    proof_submitted: LegacyMap<(u128, ContractAddress), bool>,
}

#[event]
fn EventCreated(event_id: u128, organizer: ContractAddress, deposit_amount: u128, token: ContractAddress) {}

#[event]
fn RsvpReceived(event_id: u128, attendee: ContractAddress) {}

#[event]
fn AttendanceAccepted(event_id: u128, attendee: ContractAddress) {}

#[event]
fn EventFinalized(event_id: u128, organizer: ContractAddress, refunded: u128, forfeited: u128) {}

#[abi]
trait IEventRsvp {
    fn create_event(ref self: ContractState, deposit_amount: u128, token: ContractAddress) -> u128;
    fn get_event(self: @ContractState, event_id: u128) -> Event;
    fn rsvp(ref self: ContractState, event_id: u128);
    fn submit_attendance_proof(ref self: ContractState, event_id: u128, zk_proof: Array<u8>);
    fn finalize_event(ref self: ContractState, event_id: u128);
}

#[contract]
impl EventRsvp of IEventRsvp {
    fn create_event(ref self: ContractState, deposit_amount: u128, token: ContractAddress) -> u128 {
        let organizer = get_caller_address();
        let id = self.next_event_id.read();
        self.next_event_id.write(id + 1_u128);

        let event = Event {
            organizer, token, deposit_amount, attendee_count: 0_u32, finalized: false
        };
        self.events.write(id, event);

        EventCreated(id, organizer, deposit_amount, token);
        id
    }

    fn get_event(self: @ContractState, event_id: u128) -> Event {
        self.events.read(event_id)
    }

    fn rsvp(ref self: ContractState, event_id: u128) {
        let caller = get_caller_address();
        let mut event = self.events.read(event_id);
        assert(!event.finalized, 'EVENT_FINALIZED');

        // Ensure not already RSVP'd
        let has = self.attending.read((event_id, caller));
        assert(!has, 'ALREADY_RSVP');

        // Pull deposit from caller (ERC20 transferFrom)
        erc20_transfer_from(event.token, caller, contract_address(), event.deposit_amount);

        self.attending.write((event_id, caller), true);
        event.attendee_count = event.attendee_count + 1_u32;
        self.events.write(event_id, event);

        RsvpReceived(event_id, caller);
    }

    fn submit_attendance_proof(ref self: ContractState, event_id: u128, zk_proof: Array<u8>) {
        let caller = get_caller_address();
        let event = self.events.read(event_id);
        assert(!event.finalized, 'EVENT_FINALIZED');

        // Must have RSVP'd
        let has = self.attending.read((event_id, caller));
        assert(has, 'NOT_RSVP');

        // MOCK verifier: accept if zk_proof == bytes("OK")
        let ok = array_eq_bytes(zk_proof, b"OK");
        assert(ok, 'INVALID_PROOF');

        self.proof_submitted.write((event_id, caller), true);
        AttendanceAccepted(event_id, caller);
    }

    fn finalize_event(ref self: ContractState, event_id: u128) {
        let caller = get_caller_address();
        let mut event = self.events.read(event_id);
        assert(caller == event.organizer, 'ONLY_ORGANIZER');
        assert(!event.finalized, 'EVENT_FINALIZED');

        // In a real app, you'd iterate stored attendees.
        // For a beginner version, organizer passes attendee addresses off-chain
        // and calls batch_refund(...) to avoid unbounded iteration on-chain.
        // For simplicity here, we assume small events and a static list passed in frontend.

        // Minimal flag set:
        event.finalized = true;
        self.events.write(event_id, event);

        // NOTE: To actually refund & forfeit, add a separate function:
        // - batch_refund(event_id, attendees: Array<ContractAddress>)
        // - for each: if proof_submitted -> transfer deposit back
        // - else -> accumulate forfeits, transfer to organizer
        // This avoids large loops in a single tx.

        EventFinalized(event_id, event.organizer, 0_u128, 0_u128);
    }
}

//  -------------------- Helpers -------------------- 

fn contract_address() -> ContractAddress {
    starknet::contract_address::contract_address_const()
}

extern "C" fn erc20_transfer_from(
    token: ContractAddress, 
    owner: ContractAddress, 
    to: ContractAddress, 
    amount: u128
) {
    // call ERC20 transferFrom(owner, to, amount)
    // selector for transferFrom
    let selector = starknet::selector!("transferFrom");
    let mut calldata = ArrayTrait::new();
    calldata.append(owner.into());
    calldata.append(to.into());
    calldata.append(amount.into());
    let _ret = call_contract_syscall(token, selector, calldata.span()).unwrap_syscall();
}

fn array_eq_bytes(a: Array<u8>, b: @Array<u8>) -> bool {
    if a.len() != b.len() { return false; }
    let mut i = 0_usize;
    while i < a.len() {
        if a.at(i) != b.at(i) { return false; }
        i = i + 1;
    }
    true
}

// Production notes

// Replace array_eq_bytes(zk_proof, "OK") with a real verifier (e.g., pass a verifier contract address and call it).

// Avoid unbounded iteration on-chain. Use batch functions and cap input sizes per call.

// Use a robust ERC20 (OpenZeppelin Cairo implementations) and thorough checks on transferFrom results.