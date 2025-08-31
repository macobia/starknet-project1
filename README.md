A simple Guide to build two starknet project:

✅ Decentralized Event RSVP with Attendance Proof (ZK-friendly)

✅ Peer-to-Peer Skill Swap Marketplace

I’ll keep it beginner-friendly, but detailed enough to be practical. We’ll cover stack, on-chain design, key functions, events, example Cairo code, local testing, and basic frontend integration.

1. Decentralized Micro-Task Reputation SystemDescription: A platform where users post micro-tasks (e.g., “review my code snippet” or “translate a sentence”) and pay small fees in ETH. Task completers earn reputation points stored on-chain. Users can query a worker’s reputation before assigning tasks.
Why Unique?: Unlike centralized platforms like Fiverr, this uses Starknet’s low fees for micro-payments and ZK proofs for verifiable reputation without revealing sensitive data. It’s a niche not heavily explored on Starknet.
Cairo Implementation:Storage: Mapping of user addresses to reputation scores and task history.
Functions: post_task(task_description, reward), complete_task(task_id, proof), get_reputation(user_address).
Events: Emit task creation and completion events for transparency.
Starknet Advantage: Low fees make micro-payments (e.g., $0.01) viable; ZK ensures reputation is tamper-proof.
Beginner-Friendly: Simple mappings and event handling; no complex math. You can test with fake tasks locally.

2. ZK-Verified Study Group CommitmentDescription: A smart contract where students form study groups and commit to daily study hours. Each student submits a ZK proof of their study time (e.g., via an app tracking screen time). If they meet their commitment, they earn tokens; if not, their staked ETH is slashed.
Why Unique?: Combines education with accountability in a decentralized way, using ZK proofs to verify private data (study time) without revealing details. Not a common DeFi or NFT use case.
Cairo Implementation:Storage: Struct for groups (members, daily goal, stake amount), mapping of user to group.
Functions: create_group(goal_hours, stake), submit_study_proof(zk_proof), distribute_rewards().
Events: Log group creation and reward distribution.
Starknet Advantage: ZK proofs for private study data; low fees for daily submissions.
Beginner-Friendly: Focus on basic structs and conditionals; ZK proof can be mocked with a boolean for testing.


0) Stack & Prereqs
Tooling

Cairo 1 compiler (via scarb)

Scarb (Cairo package manager & build tool)

Starknet Foundry (snforge for tests, sncast for deploying & calling)

starknet-devnet-rs (fast local devnet)

Node.js (for frontend)

starknet.js (frontend wallet & contract calls)

Wallets: Argent X or Braavos (testnet)

1) Project Layout
starknet-dapps/
  ├─ event_rsvp/
  │   ├─ Scarb.toml
  │   └─ src/
  │       └─ event_rsvp.cairo
  ├─ skill_swap/
  │   ├─ Scarb.toml
  │   └─ src/
  │       └─ skill_swap.cairo
  ├─ tests/
  │   ├─ event_rsvp_test.cairo
  │   └─ skill_swap_test.cairo
  └─ frontend/
      ├─ package.json
      └─ (vite + react + starknet.js)

2) dApp A — Decentralized Event RSVP (with Attendance Proof)

Problem
People RSVP and don’t show up. We take a small refundable deposit when RSVPing. If they prove attendance, they get it back; otherwise, the organizer keeps deposits from no-shows. We’ll mock ZK verification as a boolean/bytes input so you can swap in a real verifier later.

On-chain Model
    Storage

        1. events: LegacyMap<EventId, Event>
            Event holds:

                I. organizer: ContractAddress

                II. deposit_amount: u128

                III. attendee_count: u32

                IV. finalized: bool

        2. attending: LegacyMap<(EventId, ContractAddress), bool> (RSVP status)

        3. proof_submitted: LegacyMap<(EventId, ContractAddress), bool> (attendance proof accepted)

        4. Funds: the contract holds deposits (use Starknet native ETH on testnet, or fee token on devnet). For simplicity, we’ll use ETH via Cairo’s starknet::eth::EthDispatcher (or send through payable + withdraw pattern using account transfer—see note below).

Note: On Starknet, contracts cannot initiate native ETH transfers arbitrarily; you typically integrate with an ERC20 (ETH bridged token) and call its transfer/transferFrom. To keep it beginner-friendly, we’ll model deposits as ERC20 (WETH/ETH token address configurable). On devnet, you can deploy a simple ERC20 or use a known ETH token address.

Events (logs)

    I. EventCreated(event_id, organizer, deposit_amount)

    II. RsvpReceived(event_id, attendee)

    III. AttendanceAccepted(event_id, attendee)

    IV. EventFinalized(event_id, organizer, refunded, forfeited)

Flow

    1. Organizer calls create_event(deposit_amount, token_address) → event_id.

    2. User approves deposit to contract (ERC20 approve).

    3. User calls rsvp(event_id) → contract transferFrom deposit in.

    4. At the event, user calls submit_attendance_proof(event_id, zk_proof_bytes)
    For now: we mock verifier and accept a fixed “ok” proof (or a signature).

    5. Organizer calls finalize_event(event_id) →

        I. Refund deposits for proof_submitted == true

        II. Transfer forfeits to organizer.

CODE SNIPPET -> event_rsvp/src/lib.cairo

3) dApp B — Peer-to-Peer Skill Swap Marketplace
    Problem
    Two users barter skills (e.g., I teach Python; I want Spanish). Both put a small deposit to prevent ghosting. Funds are released when both confirm completion; otherwise, a timeout lets either party claim their deposit back or resolve.

    On-chain Model
    Storage
        1. next_listing_id: u128
        2. listings: LegacyMap<ListingId, Listing>
            1. user: ContractAddress
            2. skill_offered: felt252
            3. skill_desired: felt252
            4. active: bool
        3. swaps: LegacyMap<SwapId, Swap>
            1. a: ContractAddress (creator/listing owner)
            2. b: ContractAddress (proposer)
            3. token: ContractAddress
            4. deposit: u128
            5. a_confirmed: bool
            6. b_confirmed: bool
            7. settled: bool
        Encode strings client-side to felt252 or short-strings (or store keccak/hash of strings to save space).
    Functions
        1. list_skill(skill_offered, skill_desired)
        2. propose_swap(listing_id, token, deposit) → locks deposit from both sides (needs approvals)
        3. confirm_swap(swap_id) → each side marks done
        4. settle_swap(swap_id) → when both confirmed, return both deposits; if timeout, add a dispute/abort path
    Events
        1. SkillListed(listing_id, user)
        2. SwapProposed(swap_id, a, b)
        3. SwapConfirmed(swap_id, by)
        4. SwapSettled(swap_id)
    
CODE SNIPPET -> skill_swap/src/skill_swap.cairo

4) Local Build, Test, Deploy
    Build
    cd event_rsvp && scarb build
    cd ../skill_swap && scarb build

    Tests (snforge)
    Example tests/event_rsvp_test.cairo CHECK CODE SNIPPET -> /tests/event_rsvp_test.cairo
    Run: snforge test

    Deploy (sncast → devnet/testnet)
    # Declare & deploy (adjust profile and RPC)
        sncast --profile devnet declare --contract-name event_rsvp
        sncast --profile devnet deploy --class-hash <hash> --constructor-calldata ""
        For testnet, configure ~/.snfoundry profile with RPC + account.

5) Frontend Integration (React + starknet.js)
    Install: npm i starknet @argent/get-starknet
    Connect & call: CHECK CODE SNIPPET -> frontend/

6) Security & Gas Considerations
    No unbounded loops over large sets; use batched operations.
    Check-effects-interactions: update storage before external calls.
    Token safety: handle ERC20 return values; consider known OZ ERC20.
    Access control: organizer-only finalize; participant-only confirm.
    Input validation: non-zero deposits, valid addresses.
    Upgradability (optional): proxy pattern if you need contract upgrades.

7) What to Swap Later for Production
    Replace mock proof with a real verifier (pass verifier contract address; store event’s public inputs; verify proof on-chain).
    Add batch_refund(event_id, attendees[]) for RSVP finalization.
    Add timeouts & dispute resolution in Skill Swap.
    Add indexer (e.g., Apibara, Dojo indexer) to query events & swaps for the UI.

8) Quick Demo Commands (Devnet)
    1. Deploy an ERC20 test token (or use an existing devnet token).
    2. Mint to users and approve the dApp contracts:
        # Using sncast to call ERC20 approve
        sncast --profile devnet invoke \
        --contract-address <ERC20> \
        --function approve \
        --calldata <CONTRACT_ADDR> <AMOUNT>

    3. Create Event:
        sncast --profile devnet invoke \
         --contract-address <EVENT_RSVP_ADDR> \
         --function create_event \
        --calldata <DEPOSIT_AMOUNT> <ERC20_ADDR>

    4. RSVP (after approve):
        sncast invoke --contract-address <EVENT_RSVP_ADDR> --function rsvp --calldata <EVENT_ID>
    5.  Submit Proof:
        # pass "OK" bytes — in practice encode via abi-friendly method
    6. Finalize (organizer):
        sncast invoke --contract-address <EVENT_RSVP_ADDR> --function finalize_event --calldata <EVENT_ID>


TL;DR or Summary
    Event RSVP: organizer sets deposit; users RSVP by ERC20 deposit; submit mock ZK proof (“OK”) to mark attendance; finalize & refund/forfeit with batched calls.

    Skill Swap: list skills; both parties deposit via propose_swap; both confirm; settle refunds both deposits; extend with timeouts/disputes later.

    Stack: Cairo 1 + Scarb + Foundry + Devnet + starknet.js + Argent X/Braavos.

