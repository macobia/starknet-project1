%lang starknet
use snforge_std::{ declare, ContractClassTrait, start_prank, stop_prank };
use starknet::contract_address::contract_address_from_felt252;

#[test]
fn test_create_event() {
    let class_hash = declare("event_rsvp").unwrap();
    let (contract_address, _) = snforge_std::deploy(contract_class_hash: class_hash, calldata: @[]);
    // call create_event and assert storage or events...
}
