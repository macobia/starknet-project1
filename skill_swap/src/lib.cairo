// skill_swap/src/skill_swap.cairo
%lang starknet

use starknet::ContractAddress;
use starknet::get_caller_address;
use starknet::storage::LegacyMap;
use core::traits::Into;

#[derive(Copy, Drop, Serde, PartialEq)]
struct Listing {
    user: ContractAddress,
    skill_offered: felt252,
    skill_desired: felt252,
    active: bool
}

#[derive(Copy, Drop, Serde, PartialEq)]
struct Swap {
    a: ContractAddress,
    b: ContractAddress,
    token: ContractAddress,
    deposit: u128,
    a_confirmed: bool,
    b_confirmed: bool,
    settled: bool
}

#[storage]
struct Storage {
    next_listing_id: u128,
    next_swap_id: u128,
    listings: LegacyMap<u128, Listing>,
    swaps: LegacyMap<u128, Swap>,
}

#[event]
fn SkillListed(listing_id: u128, user: ContractAddress) {}
#[event]
fn SwapProposed(swap_id: u128, a: ContractAddress, b: ContractAddress) {}
#[event]
fn SwapConfirmed(swap_id: u128, by: ContractAddress) {}
#[event]
fn SwapSettled(swap_id: u128) {}

#[abi]
trait ISkillSwap {
    fn list_skill(ref self: ContractState, skill_offered: felt252, skill_desired: felt252) -> u128;
    fn propose_swap(ref self: ContractState, listing_id: u128, token: ContractAddress, deposit: u128) -> u128;
    fn confirm_swap(ref self: ContractState, swap_id: u128);
    fn settle_swap(ref self: ContractState, swap_id: u128);
    fn get_listing(self: @ContractState, listing_id: u128) -> Listing;
    fn get_swap(self: @ContractState, swap_id: u128) -> Swap;
}

#[contract]
impl SkillSwap of ISkillSwap {
    fn list_skill(ref self: ContractState, skill_offered: felt252, skill_desired: felt252) -> u128 {
        let id = self.next_listing_id.read();
        self.next_listing_id.write(id + 1_u128);

        let user = get_caller_address();
        let listing = Listing { user, skill_offered, skill_desired, active: true };
        self.listings.write(id, listing);

        SkillListed(id, user);
        id
    }

    fn propose_swap(ref self: ContractState, listing_id: u128, token: ContractAddress, deposit: u128) -> u128 {
        let listing = self.listings.read(listing_id);
        assert(listing.active, 'LISTING_INACTIVE');

        let proposer = get_caller_address();
        let a = listing.user;
        let b = proposer;

        // Pull both deposits to contract (requires ERC20 approve by both)
        erc20_transfer_from(token, a, contract_address(), deposit);
        erc20_transfer_from(token, b, contract_address(), deposit);

        let swap_id = self.next_swap_id.read();
        self.next_swap_id.write(swap_id + 1_u128);

        let swap = Swap {
            a, b, token, deposit, a_confirmed: false, b_confirmed: false, settled: false
        };
        self.swaps.write(swap_id, swap);

        // Optional: mark listing inactive or keep for multiple swaps
        // self.listings.write(listing_id, Listing { active: false, ..listing });

        SwapProposed(swap_id, a, b);
        swap_id
    }

    fn confirm_swap(ref self: ContractState, swap_id: u128) {
        let mut swap = self.swaps.read(swap_id);
        assert(!swap.settled, 'ALREADY_SETTLED');

        let caller = get_caller_address();
        if caller == swap.a {
            swap.a_confirmed = true;
        } else if caller == swap.b {
            swap.b_confirmed = true;
        } else {
            assert(false, 'NOT_PARTICIPANT');
        }
        self.swaps.write(swap_id, swap);

        SwapConfirmed(swap_id, caller);
    }

    fn settle_swap(ref self: ContractState, swap_id: u128) {
        let mut swap = self.swaps.read(swap_id);
        assert(!swap.settled, 'ALREADY_SETTLED');

        // Basic happy path: both confirmed
        assert(swap.a_confirmed && swap.b_confirmed, 'BOTH_NOT_CONFIRMED');

        // refund both deposits
        erc20_transfer(swap.token, swap.a, swap.deposit);
        erc20_transfer(swap.token, swap.b, swap.deposit);

        swap.settled = true;
        self.swaps.write(swap_id, swap);

        SwapSettled(swap_id);
    }

    fn get_listing(self: @ContractState, listing_id: u128) -> Listing {
        self.listings.read(listing_id)
    }
    fn get_swap(self: @ContractState, swap_id: u128) -> Swap {
        self.swaps.read(swap_id)
    }
}

// -------- Helpers ----------

fn contract_address() -> ContractAddress {
    starknet::contract_address::contract_address_const()
}

extern "C" fn erc20_transfer_from(
    token: ContractAddress, owner: ContractAddress, to: ContractAddress, amount: u128
) {
    let selector = starknet::selector!("transferFrom");
    let mut calldata = ArrayTrait::new();
    calldata.append(owner.into());
    calldata.append(to.into());
    calldata.append(amount.into());
    let _ret = starknet::syscalls::call_contract_syscall(token, selector, calldata.span()).unwrap_syscall();
}

extern "C" fn erc20_transfer(token: ContractAddress, to: ContractAddress, amount: u128) {
    let selector = starknet::selector!("transfer");
    let mut calldata = ArrayTrait::new();
    calldata.append(to.into());
    calldata.append(amount.into());
    let _ret = starknet::syscalls::call_contract_syscall(token, selector, calldata.span()).unwrap_syscall();
}


// Production ideas

// Add timeout & dispute: if one side ghosts, let the other cancel after deadline (forfeit half or full).

// Add reputation mapping (increment after successful swaps).

// Support multiple tokens and variable deposit per listing.