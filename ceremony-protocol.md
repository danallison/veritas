# The Veritas Ceremony Protocol

A general protocol for producing verifiable shared randomness among mutually distrustful parties.

---

## 1. Motivation

Many situations require a random outcome that all parties trust: who goes first, how a resource is divided, which name is drawn from a hat. The usual approaches have a common flaw — someone is in a position to cheat. If Alice flips the coin, Bob must trust Alice. If a website generates the number, everyone must trust the website.

The Ceremony Protocol eliminates this problem by separating two acts that are normally entangled:

1. **Committing to accept an outcome** (before it is known)
2. **Determining the outcome** (after all parties are committed)

By enforcing a strict temporal boundary between these two acts — and by distributing the determination of randomness so that no single party controls it — the protocol makes cheating either impossible or publicly detectable.

---

## 2. Definitions

**Ceremony.** A ceremony is a bounded process that begins with a question ("who goes first?", "which item does each person get?") and ends with a random answer that all parties have committed to accept. A ceremony is the atomic unit of the protocol. It either completes — producing a verified outcome — or it fails explicitly. It never produces an ambiguous result.

**Party.** Any individual or entity that has a stake in the outcome of a ceremony. A party may be a participant (someone who commits to accepting the outcome) or a witness (someone who observes and can verify the process but is not bound by the outcome).

**Initiator.** The party who defines a ceremony by specifying its parameters. The initiator has no special power over the *outcome* — they cannot influence which result the entropy produces. However, the initiator has agenda-setting power: they choose what question is asked, what options are on the list, and (for weighted selections) what the weights are. All parties can inspect the parameters before committing, and should satisfy themselves that the parameters are fair before doing so. Defining a ceremony is an administrative act, not a privileged one, but it is not a neutral one.

**Officiant.** The party responsible for executing the protocol: collecting commitments, enforcing deadlines, combining entropy, computing outcomes, and maintaining the record. The officiant is a *role*, not a trusted authority. The protocol is designed so that the officiant cannot influence the outcome (under the participant-contributed entropy method) or so that any influence is publicly detectable (under other methods). In a software implementation, the server is the officiant. In a physical setting, this could be a notary, a neutral third party, or a rotating role.

**Commitment.** An irrevocable, authenticated statement by a party that says: *"I will accept the outcome of this ceremony, whatever it may be."* A commitment is bound to a specific ceremony and a specific party. It cannot be transferred, reused, or applied retroactively. The critical property is that a commitment is made — and is irrevocable — before any information about the outcome is available to any party. The strength of the authentication — and therefore the strength of the non-repudiation guarantee — depends on the identity mode (see Section 10).

**Entropy.** The raw unpredictable input from which the outcome is derived. Entropy may come from participants, from an external source, or from both. The protocol defines how entropy is contributed, verified, and combined.

**Outcome.** The result of the ceremony: a deterministic function of the combined entropy and the ceremony parameters. Given the same entropy and parameters, any party can independently recompute and verify the outcome.

**Record.** An ordered, tamper-evident account of every event in the ceremony: its creation, each commitment, each entropy contribution, and the final outcome. The record exists so that any party — including parties not involved in the ceremony — can verify after the fact that the protocol was followed correctly.

---

## 3. Ceremony Parameters

Every ceremony is defined by the following parameters, which are fixed at creation and cannot be changed once any party has committed:

- **Ceremony identity.** A unique identifier for this ceremony, distinguishing it from all other ceremonies. In a software system, this is a UUID or similar. In a physical setting, it should be a description specific enough to prevent confusion — e.g., "Draft order for the 2026 fantasy league, initiated by Alice on March 1st." The ceremony identity is included in entropy seals (Method A) to prevent replay across ceremonies.

- **Question.** A description of the decision to be made. ("Who picks the restaurant?", "What order do we draft in?")

- **Outcome type.** The structure of the random answer. Examples:
  - *Binary choice* (heads/tails, yes/no)
  - *Selection* (pick one from a named list)
  - *Ordering* (random permutation of a list)
  - *Numeric* (integer within a range)
  - *Weighted selection* (pick one, with specified probabilities)

- **Derivation rule.** The deterministic function that maps combined entropy to an outcome. For standard outcome types, this is implied (see Section 6), but it must be unambiguous. Any party should be able to recompute the outcome from the combined entropy and these parameters alone.

- **Required parties.** The number of commitments needed before the ceremony can proceed. This is a threshold, not an exact count. Once the required number of commitments are in, the ceremony *may* proceed to Phase 3. Whether it does so immediately or waits for the commitment deadline is controlled by the commitment mode (see below).

- **Commitment mode.** Whether the ceremony proceeds as soon as the required number of commitments are in (*immediate*), or waits until the commitment deadline even if enough parties have committed (*deadline-wait*). Immediate mode is appropriate when the parties are known in advance. Deadline-wait mode is appropriate when the ceremony is open to anyone who wants to join (e.g., a raffle) and the final participant list is not known until the deadline.

- **Commitment deadline.** A point in time after which no further commitments will be accepted. If the required number of commitments have been received, the ceremony proceeds. If not, it expires.

- **Entropy method.** How randomness will be sourced (see Section 5).

- **Entropy combination procedure.** How multiple entropy contributions are combined into a single value. For most cases this is concatenation in canonical order followed by hashing, but it must be specified. The canonical ordering of participants (e.g., alphabetical by name, or by order of commitment) must also be fixed here.

- **Reveal deadline** (Methods A and D only). A point in time by which all participants must reveal their sealed entropy values. If a participant has not revealed by this deadline, the non-participation policy is applied.

- **Non-participation policy** (Methods A and D only). What happens if a participant commits but fails to reveal their entropy by the reveal deadline (see Section 7).

- **Identity mode.** How participant identity is established and how commitments are authenticated. The three modes — anonymous, authenticated, and self-certified — offer different tradeoffs between convenience and non-repudiation (see Section 10).

---

## 4. The Protocol

The ceremony proceeds through a strict sequence of phases. Each phase has an entry condition and a completion condition. The protocol never moves backward.

### Phase 1: Definition

The initiator creates the ceremony by specifying its parameters (Section 3). The officiant records the ceremony's creation in the record. No commitments have been made. No entropy has been generated. The ceremony parameters are public — any potential party can inspect them before deciding whether to commit.

**Entry condition:** None.
**Completion condition:** The ceremony parameters are recorded.

### Phase 2: Commitment

Parties examine the ceremony parameters and decide whether to participate. Each party who chooses to participate makes a commitment: an authenticated, irrevocable statement binding them to the outcome.

If the entropy method requires participants to contribute entropy (see Section 5, Methods A and D), each party also prepares a *sealed entropy contribution* at this time. The sealed contribution is submitted alongside the commitment but cannot be read by anyone — including the officiant — until Phase 3. The sealing mechanism depends on the implementation:

- In a software system: a cryptographic hash of the entropy value (a *commitment hash*).
- In a physical setting: a written value in a sealed, opaque envelope, handed to the officiant.

The commitment phase is open until the commitment deadline passes, or — if the commitment mode is *immediate* — until the required number of parties have committed, whichever comes first.

If the deadline passes without enough commitments, the ceremony expires. No outcome is produced, so no party is bound to any result. (Commitments are irrevocable in the sense that a party cannot unilaterally withdraw — but a commitment to accept the outcome of a ceremony that produces no outcome is vacuously satisfied.) If the commitment mode is *deadline-wait*, the ceremony proceeds only after the deadline, even if enough commitments arrived earlier.

**Entry condition:** Ceremony parameters are recorded.
**Completion condition:** The commitment deadline has passed with enough commitments, OR (in *immediate* mode) the required number of commitments are recorded.

**The Commitment Boundary.** The transition from Phase 2 to Phase 3 is the critical moment of the protocol. Before this boundary, the ceremony may still fail — the deadline may pass without enough commitments, and the ceremony expires with no outcome. After this boundary, the ceremony proceeds to entropy collection. (The ceremony may still fail after this point — for example, if all participants refuse to reveal and the non-participation policy is cancellation — but no party can withdraw their commitment.) Individual commitments are irrevocable from the moment they are made, but the commitment boundary is the point at which the ceremony as a whole becomes irrevocable: entropy collection begins, and information about the outcome may start to become available. The protocol's fairness depends entirely on the guarantee that *no information about the outcome is available to any party before this boundary is crossed.*

### Phase 3: Entropy

Randomness is collected according to the entropy method specified in the ceremony parameters. The specific procedure depends on the method (see Section 5), but in every case the following invariant holds:

> **The Entropy Ordering Invariant.** No party has access to any information that could allow them to predict the outcome at the time they make their commitment.

This invariant is what distinguishes the protocol from informal randomness ("I'll flip a coin — trust me"). It is maintained differently depending on the entropy method:

- **Participant-contributed entropy (Method A):** Entropy values are sealed during Phase 2 and revealed only now. No party can change their contribution after seeing others'.
- **External source (Method B):** The entropy comes from a source whose output is determined after the commitment deadline — typically a future event whose value no party controls.
- **Officiant-generated (Method C):** The officiant generates entropy using a verifiable process. This method requires trust in the officiant but provides proof that the output was derived from declared inputs.
- **Combined (Method D):** Both the Method A and Method B invariants apply. Participant entropy is sealed before any reveals, and the external source value is not yet determined at commitment time.

At the end of this phase, all entropy contributions are collected and recorded.

**Entry condition:** The required number of commitments are in, and either the commitment mode is *immediate* or the commitment deadline has passed.
**Completion condition:** All required entropy has been collected and recorded, or the reveal deadline has passed (triggering the non-participation policy).

### Phase 4: Resolution

The outcome is computed. This is a deterministic, reproducible calculation:

1. All entropy contributions are combined into a single value, using a fixed combination procedure specified in the ceremony parameters. The combination must be deterministic — the same inputs always produce the same combined value — and order-independent (or use a canonical ordering known in advance).

2. The combined entropy is applied to the outcome type to produce the result. This derivation must also be deterministic: given the ceremony parameters and the combined entropy, any party can independently arrive at the same outcome.

The officiant computes and announces the outcome. The outcome and its derivation (all inputs, the combination procedure, and the result) are recorded.

**Entry condition:** All entropy has been collected.
**Completion condition:** The outcome is computed and recorded.

### Phase 5: Finalization

The ceremony is sealed. The complete record — from creation through outcome — is finalized and made available to all parties. Any party (or any outside observer with access to the record) can now verify:

1. That the ceremony parameters were fixed before any commitment was made.
2. That all commitments were made before any entropy was revealed.
3. That all entropy contributions are authentic (sealed values match revealed values, external sources match public records, etc.).
4. That the outcome was correctly derived from the combined entropy and ceremony parameters.

The ceremony is now complete. The outcome is binding on all committed parties.

**Entry condition:** The outcome is recorded.
**Completion condition:** The record is finalized and available to all parties.

---

## 5. Entropy Methods

### Method A: Participant-Contributed Entropy

Each participant contributes their own randomness. No single party — including the officiant — can control or predict the outcome, as long as at least one participant's contribution is genuinely random.

**Procedure:**

1. *Sealing (during Phase 2).* Each participant independently generates a random value. They produce a sealed version of this value — one that commits them to the value without revealing it. They submit the sealed version alongside their commitment.

2. *Revealing (Phase 3).* After all commitments are in, each participant submits their original value to the officiant. The officiant collects all reveals privately — individual reveals are not published to other participants as they arrive. Once all reveals are in (or the reveal deadline has passed), the officiant publishes all revealed values simultaneously and verifies that each matches its seal.

   This batching is essential. If reveals were published incrementally, a later revealer could compute the outcome before deciding whether to reveal — giving them a strategic advantage (default if the outcome is unfavorable, reveal if it is favorable). Batched reveals ensure that no participant sees others' revealed values during the reveal window, closing this attack entirely.

3. *Combining (Phase 4).* The revealed values are combined in a canonical order (e.g., alphabetical by participant name) to produce the ceremony's entropy.

**Sealing mechanisms:**

| Implementation | Seal | Verification |
|----------------|------|--------------|
| Software (cryptographic) | Hash of the value: `H(ceremony_id, party_id, value)` | Recompute hash from revealed value; compare. |
| Physical (envelope) | Value written on paper, placed in a tamper-evident envelope, signed across the seal, and handed to the officiant. | Officiant opens envelope in the presence of all parties; compares to any prior claims. |
| Physical (split knowledge) | Value written on paper, sealed, given to two independent witnesses who do not communicate. | Both witnesses confirm the sealed value matches the revealed value. |

**Security property:** Even if all parties except one collude, the outcome remains unpredictable, because it depends on the one honest party's sealed contribution, which was fixed before any information was available. This property holds *given that the sealing mechanism is binding* — a sealed value cannot be changed or read before the reveal phase. Cryptographic sealing (hash commitment) provides a strong binding guarantee. Physical sealing (envelopes) provides an approximate one: it relies on the tamper-evident properties of the envelope and on the presence of witnesses. In a physical setting where the officiant is also colluding, the envelope-based guarantee is weaker — the officiant could attempt to open an envelope early or substitute it — so the physical protocol depends on the sealing being genuinely tamper-evident and on reveals being conducted in the presence of all parties.

This property also assumes that at least one party generates genuinely unpredictable entropy. A party who chooses a predictable value (e.g., always sealing "1") has followed the protocol but has not contributed meaningful randomness. The protocol cannot verify that entropy is "truly random" — it can only ensure that no party sees others' entropy before committing their own. The guarantee is: *if* at least one party's entropy is unpredictable, the outcome is unpredictable.

**Validity of contributions.** In the cryptographic case, entropy is opaque bytes and validity is not an issue. In the physical case, the ceremony parameters should specify the form of a valid contribution (e.g., "an integer between 1 and 1,000,000"). If a revealed value does not conform — it is illegible, out of range, or not of the specified form — it should be treated as a non-reveal and handled according to the non-participation policy.

**Failure mode:** A participant may refuse to reveal after seeing others' commitments (see Section 7).

### Method B: External Source

Entropy comes from a predetermined external event whose outcome is not yet known at the time commitments are made.

**Procedure:**

1. *Designation (Phase 1).* The ceremony parameters specify an external source and a specific future event — for example, a future round of a public randomness beacon, or a publicly observable event (closing stock price on a future date, last digits of a future lottery drawing, etc.).

2. *Collection (Phase 3).* After the designated event occurs, the officiant records its value, including any available proof of authenticity (digital signatures from the source, references to published records, newspaper clippings, etc.).

3. *Derivation (Phase 4).* The outcome is derived from the external value and the ceremony identity, ensuring that different ceremonies using the same external event produce different outcomes.

**Security property:** The security of this method depends on no party controlling or influencing the external source. Care should be taken in choosing the source — a public randomness beacon (such as drand) is designed for this purpose, while a stock price or sports score may be influenceable by a sufficiently resourced party. Any party can independently verify the external value against the public record.

**Failure mode:** The external source might fail to produce a value (service outage, canceled event). The ceremony parameters should specify a fallback or expiration in this case.

### Method C: Officiant-Generated

The officiant produces the entropy. This method requires trust in the officiant but provides transparency.

In a software implementation, the officiant can use a Verifiable Random Function (VRF): a function that produces a random-looking output from a given input, along with a mathematical proof that the output was correctly derived. Anyone with the officiant's public key can verify the proof. The officiant cannot choose the output — it is determined by the input — but the officiant does choose *when* to evaluate the function.

In a physical setting, this is equivalent to the officiant rolling dice, drawing from a shuffled deck, or using a mechanical randomness device — in the presence of witnesses.

**Security property:** The officiant can prove they did not choose the output arbitrarily. However, the officiant has a selective-abort advantage: they could evaluate the VRF before committing to the ceremony (or before publishing the result), and decline to proceed if the outcome is unfavorable. If the VRF input is derived entirely from data already committed to the record (e.g., the ceremony identity and the collected commitment hashes), the officiant cannot vary the input once the ceremony is underway — but they could have chosen not to create the ceremony in the first place, or could refuse to publish the outcome. This method is therefore suitable for cases where the officiant is a sufficiently trusted neutral party, or where the stakes are low enough that this risk is acceptable.

### Method D: Combined

Participant-contributed entropy and an external source are combined. This provides defense in depth: even if the external source is compromised, participant entropy preserves unpredictability; even if participants collude, the external source prevents prediction.

**Procedure:**

Method D follows the Method A procedure for participant entropy (sealing during Phase 2, batched reveal during Phase 3) and the Method B procedure for external entropy (collection during Phase 3). The two are then combined (Phase 4) using the ceremony's specified combination procedure (e.g., concatenation followed by hashing).

**Phase 3 ordering constraint:** Participant reveals must complete (or the reveal deadline must pass and the non-participation policy must be applied) *before* the external source value is collected. If the external value were available during the reveal window, every participant could compute the outcome before deciding whether to reveal — giving all of them the strategic-default advantage, which is strictly worse than Method A alone. The correct ordering ensures that no participant knows the full combined entropy at the time they make their reveal-or-default decision.

In practice, this means the designated external event should be scheduled to occur *after* the reveal deadline, or the officiant should defer collecting the external value until all reveals are in.

---

## 6. Deterministic Outcome Derivation

The derivation of the outcome from the combined entropy must be a publicly known, deterministic function. This is what allows any party to independently verify the result. The function depends on the outcome type:

- **Binary choice.** Interpret the entropy as a number; if even (or below a threshold), one option; if odd (or above), the other.

- **Selection from a list of N items.** Interpret the entropy as a number and select an item from the canonical ordering specified at ceremony creation. Care must be taken to avoid *modular bias*: if the entropy has K equally likely values and K is not a multiple of N, then a naive remainder operation (`entropy mod N`) makes some items slightly more likely than others. This can be mitigated by using entropy much larger than N (so the bias becomes negligible) or by rejection sampling (discarding and re-deriving if the value falls in the biased range). In a physical setting with small N, this is easily avoided by choosing the entropy range to be a multiple of N.

- **Ordering (permutation) of N items.** Use the entropy to perform a deterministic shuffle — for example, by successively deriving sub-values and using each to select from the remaining items (a deterministic Fisher-Yates shuffle). Each selection step is subject to the same modular bias concern as above.

- **Integer in a range [lo, hi].** Interpret the entropy as a number in the range. The same modular bias concern applies if the entropy space is not a multiple of the range size.

- **Weighted selection.** Interpret the entropy as a point in the interval [0, 1), and select the item whose cumulative weight range contains that point.

The specific derivation procedure must be fixed and public. Any party who has the combined entropy and the ceremony parameters can execute the derivation and confirm the result.

---

## 7. Non-Participation and Failure

### Refusal to Reveal (Methods A and D)

A participant who has committed and sealed an entropy value may refuse to reveal it, stalling the ceremony. This is the primary liveness risk in Methods A and D. The ceremony parameters must specify a non-participation policy, chosen at creation:

- **Default substitution.** The officiant substitutes a deterministic, publicly known value for the non-revealing party's entropy (e.g., a value derived from the participant's identity and the ceremony identity). This allows the ceremony to proceed. The other participants' genuine entropy still ensures unpredictability — *provided there are at least three parties.* **Warning:** In a two-party ceremony, default substitution is unsafe. If Alice knows that Bob's default entropy will be a specific deterministic value, she can choose her own sealed entropy to produce a favorable outcome in the case that Bob defaults. Since Alice seals before knowing whether Bob will default, this is a gamble — but it gives Alice a strategy that is strictly better than random. If there is any chance Alice can influence whether Bob defaults (e.g., by making the reveal inconvenient for him), she gains meaningful control over the outcome. For two-party ceremonies, use exclusion or cancellation instead.

- **Exclusion.** The non-revealing party is removed and the ceremony resolves with the remaining entropy. The record notes the default. Note: if exclusion reduces the ceremony to a single participant, that participant's entropy alone determines the outcome. The participant already knows their own entropy, so they learn the outcome at the moment of exclusion. This does not violate the Entropy Ordering Invariant (they committed before knowing others would default), but it does mean the remaining participant could in principle have optimized their entropy for this scenario. This risk is inherent when the ceremony degrades to a single entropy source.

- **Cancellation.** The ceremony is aborted. No outcome is produced.

Any of these outcomes is recorded in the record, so a pattern of non-participation by a given party is publicly visible across ceremonies.

### Deadline Expiry

If the commitment deadline passes without enough commitments, the ceremony expires. No party is bound. This is a normal, non-failure outcome — it simply means there was insufficient interest.

### External Source Failure (Method B)

If the designated external event does not occur, the ceremony parameters should specify a fallback: an alternative source, an extended deadline, or cancellation.

---

## 8. The Record

Every ceremony produces a record: an ordered sequence of entries, one for each event. The record is the protocol's mechanism for accountability and verifiability.

### Required Entries

The record must contain, in order:

1. **Ceremony created.** The full ceremony parameters.
2. **Commitment received** (one entry per party). The party's identity and their sealed entropy value (if applicable).
3. **Entropy revealed / collected** (one entry per contribution). The revealed values, external source values, or officiant-generated values with proofs.
4. **Non-participation applied** (if applicable). If the reveal deadline passes with unrevealed entropy, the record must note which parties failed to reveal and what policy was applied: default substitution (recording the substituted value), exclusion (recording the party's removal), or cancellation. This entry occurs between entropy collection and outcome computation.
5. **Outcome computed.** The combined entropy, the derivation procedure applied, and the result.
6. **Ceremony finalized.** A marker that the ceremony is complete.

If the ceremony fails (expiry, cancellation, dispute), the record contains a corresponding failure entry with the reason.

### Tamper Evidence

Each entry in the record references the preceding entry in a way that makes retrospective modification detectable. In a cryptographic implementation, each entry contains a hash of the previous entry, forming a hash chain. In a physical implementation, this can be approximated by:

- Sequential numbering with no gaps.
- Each entry signed by the officiant and at least one witness.
- Copies of the record distributed to all parties as entries are made, so that any later alteration would conflict with a party's copy.

The purpose of the record is not to *prevent* tampering (that is impossible without assumptions about storage) but to make tampering *detectable*. A valid record is one where every entry is consistent with its predecessor. An invalid record is proof of misconduct.

### Verification

Any party can verify a ceremony by checking:

1. **Chain integrity.** Each entry correctly references its predecessor.
2. **Temporal ordering.** All commitments precede all entropy revelations.
3. **Seal validity.** Each revealed entropy value matches its seal from the commitment phase.
4. **Derivation correctness.** The outcome follows deterministically from the combined entropy and ceremony parameters.
5. **Completeness.** No entries are missing; the required number of commitments are present; entropy contributions account for all committed parties (either a reveal, a default substitution, or an exclusion entry for each); and the outcome is present.

If all checks pass, the ceremony is verified: the outcome is the authentic result of the protocol. If any check fails, the ceremony is disputed: the record itself is evidence of what went wrong.

---

## 9. Security Properties

The Ceremony Protocol provides the following guarantees, subject to the stated assumptions:

### Unpredictability

*No party can predict the outcome at the time they commit.*

This follows from the Entropy Ordering Invariant (Section 4, Phase 3). Under Method A, each party's entropy is sealed before any entropy is revealed, so the combined entropy — and therefore the outcome — is unknown at commitment time — *assuming at least one party's sealed entropy is genuinely unpredictable.* The protocol enforces the ordering (seal before reveal) but cannot verify the quality of any party's entropy. A party who always seals the same value has followed the protocol but contributed no randomness. The guarantee is conditional: if at least one party contributes genuine entropy, the outcome is unpredictable to all parties.

Under Method B, the external source has not yet produced its value. Unpredictability holds if the source is independent of all parties' actions. (Care should be taken in choosing external sources — a stock price, for instance, may be influenceable by a sufficiently resourced party.)

Under Method D (combined), either condition is sufficient: if participant entropy is genuine, the outcome is unpredictable even if the external source is compromised, and vice versa.

Under Method C, unpredictability holds if the officiant is honest (does not pre-compute the VRF).

### Non-Manipulation

*No single party can control the outcome.*

Under Method A, the outcome depends on every participant's entropy. A coalition of all-but-one participants cannot predict or control the outcome, because it depends on the honest party's sealed value. Under Method B, no party controls the external source. Under Method D, both conditions reinforce each other.

Under Method C, the officiant has limited influence (see Section 5).

### Irrevocability

*Once a party has committed, they cannot uncommit.*

This is a social and legal property, not a cryptographic one. In a software system, the commitment is recorded and signed. In a physical setting, the commitment is witnessed. The record provides evidence that the commitment was made. The protocol does not (and cannot) physically prevent a party from refusing to honor the outcome — but it provides proof that they committed to it.

The strength of this property depends on the identity mode (see Section 10). Under anonymous participation, the record proves that *some entity* committed, but not *which entity in the real world*. Under authenticated participation, the record ties the commitment to a verified real-world identity. Under self-certified participation, the record ties the commitment to a cryptographic key whose holder cannot plausibly deny involvement.

### Verifiability

*Any party — including parties not involved in the ceremony — can verify that the protocol was followed.*

This follows from the record (Section 8). Given the complete record, verification is a mechanical procedure (Section 8, Verification). The verifier needs no trust relationship with any party; they only need the record and the publicly known derivation procedures.

### Determinism

*The outcome is a mathematical fact, not a judgment.*

Given the combined entropy and the ceremony parameters, the outcome is determined by a fixed, public function. Two parties who independently apply this function to the same inputs will always get the same result. The officiant announces the outcome but does not decide it.

### Officiant as Participant

The protocol does not require the officiant to be a disinterested third party. In many real-world settings, one of the participants will also serve as officiant (e.g., two friends settling a bet, one of whom runs the ceremony). The safety of this arrangement depends on the entropy method and sealing mechanism:

- **Method A with cryptographic sealing:** Safe. The officiant-participant sees hash commitments, which reveal nothing about the entropy values. They seal their own entropy under the same hash commitment scheme. They cannot learn others' entropy before revealing, and cannot change their own after committing.

- **Method A with physical sealing:** Risky. The officiant holds the sealed envelopes. An officiant-participant could open their own envelope last, or attempt to read others' envelopes before the reveal phase. Mitigation: an independent witness should hold the officiant-participant's envelope, or all envelopes should be opened simultaneously in the presence of all parties.

- **Method B (external source):** Safe. The officiant has no more control over the external source than any other party.

- **Method C (officiant-generated):** Incompatible. If the officiant is also a participant with a stake in the outcome, Method C provides no protection — the officiant could evaluate the VRF privately and decline to create the ceremony if they dislike the result. Method C should only be used when the officiant is a neutral party.

- **Method D (combined):** Same considerations as Method A — safety depends on the sealing mechanism. The external source component adds no additional risk from the officiant, since they cannot control it.

---

## 10. Participant Identity

The core protocol (Sections 1–9) is deliberately silent on how a party's identity is established. It requires that commitments be *authenticated* — tied to a specific party in a way that the party cannot later deny — but does not prescribe the authentication mechanism. This section addresses that gap.

The identity question matters most when a party might deny their commitment after an unfavorable outcome. The protocol needs enough identity assurance that such denial is either impossible or implausible. Different contexts demand different levels of assurance, so the protocol supports three identity modes, chosen at ceremony creation.

### Mode 1: Anonymous

Parties are identified by opaque tokens (e.g., a UUID generated at the time of participation). No real-world identity is attached to the token. This is appropriate when the stakes are low and all parties trust each other — a coin flip between friends, a casual raffle.

**What it proves:** The same token committed and (if applicable) revealed. **What it doesn't prove:** Who the token belongs to. A party can plausibly deny involvement by claiming the token was not theirs.

**Appropriate for:** Low-stakes ceremonies among mutually trusting parties.

### Mode 2: Authenticated

Parties prove their identity through a trusted external authority — an OAuth provider (Google, GitHub), an organizational directory, or a physical witness who can vouch for identities. The commitment is tied to the verified identity, and the record shows which real-world identity made each commitment.

**What it proves:** The holder of a specific real-world account (or the person identified by a witness) committed. **What it doesn't prove:** That the account itself is trustworthy — a compromised account could be used to make commitments the real owner did not intend.

**Appropriate for:** Social ceremonies where participants are humans, UX friction should be low, and participants should not need to understand cryptography.

### Mode 3: Self-Certified

Parties identify themselves by cryptographic keypair. No external authority is needed — the ceremony record itself contains all the evidence required to prove participation. This mode adds a **roster acknowledgment** phase between commitment collection and entropy collection.

**Procedure:**

1. *Registration.* Each party registers a public key with the ceremony. No commitments have been made yet.

2. *Roster acknowledgment.* Once all required parties have registered, the officiant publishes the roster: the ordered list of (party identifier, public key) pairs. Each party then signs the roster — producing a statement that says: *"I have seen the roster for this ceremony, I confirm that my public key is correctly listed, and I am proceeding."* The signed roster acknowledgments are recorded.

3. *Commitment.* Each party signs their commitment with the same key used in the roster acknowledgment. The signature, the public key, and the commitment data are all recorded.

The record now contains three layers of evidence for each party: (a) their public key, registered before commitments began; (b) their signature over the full roster, proving they saw who else was participating and chose to proceed; (c) their signed commitment, binding them to the outcome. To deny involvement, a party would have to claim that their private key was compromised — a much stronger claim than "that wasn't me," because it requires explaining how the key was compromised and why they did not object when the roster was published with their key on it.

**What it proves:** The holder of a specific cryptographic key registered, acknowledged the roster, and committed. **What it doesn't prove:** The real-world identity behind the key — but for contexts where the key *is* the identity (e.g., software agents, services with well-known public keys), this is sufficient.

**Appropriate for:** High-stakes ceremonies, AI agent coordination, and any context where parties can manage cryptographic keys and want the strongest non-repudiation guarantee without depending on an external identity provider.

### Identity Mode as Ceremony Parameter

The identity mode is a ceremony parameter, fixed at creation like all other parameters. Parties can inspect the identity mode before deciding whether to commit. A party who requires strong non-repudiation should not commit to an anonymous ceremony; a party who values privacy should not commit to an authenticated ceremony.

The choice of identity mode does not affect the entropy methods, the derivation procedure, or the structure of the record. It affects only the authentication mechanism for commitments and (in Mode 3) adds the roster acknowledgment step between Phase 2 and Phase 3.

---

## 11. Physical Instantiation

The protocol can be executed without any software. The following is a complete example for a two-party coin toss using Method A (participant-contributed entropy).

**Materials:** Two opaque envelopes, two slips of paper, a pen, and one witness (acting as officiant).

**Procedure:**

1. **Definition.** The officiant writes on a sheet of paper: *"Ceremony: coin toss between Alice and Bob, February 18 2026, at Carol's kitchen table. Outcome type: binary (heads or tails). Required parties: 2. Commitment mode: immediate. Entropy method: participant-contributed. Each party writes an integer between 1 and 1,000,000. Combination: add the two numbers. Derivation rule: if the sum is even, 'heads'; if odd, 'tails.' Non-participation policy: cancellation. Commitment deadline: the next five minutes. Reveal deadline: immediately upon opening (the officiant opens both envelopes at once)."* Both parties read and confirm.

2. **Commitment and sealing.** Alice and Bob each privately write an integer between 1 and 1,000,000 on a slip of paper. Each places their slip in an envelope, seals it, and signs across the seal. They hand their envelopes to the officiant. By handing over the sealed envelope, each party is committing to accept the outcome. The officiant confirms receipt of both envelopes.

3. **Revelation.** The officiant opens both envelopes in the presence of both parties. Alice's number is 472,811. Bob's number is 39,504.

4. **Resolution.** The outcome is derived by a pre-agreed rule: add the two numbers; if the sum is even, "heads"; if odd, "tails." The sum is 512,315, which is odd. The outcome is "tails."

5. **Finalization.** The officiant writes the full record: the ceremony parameters, both sealed values, the sum, and the outcome. Alice and Bob each receive a copy. The ceremony is complete.

**Why this works:** Neither Alice nor Bob knew the other's number when they sealed their own. Neither could change their number after seeing the other's envelope. The sum depends on both numbers, so neither party alone controlled whether it was even or odd. The officiant had no influence — they only opened envelopes and performed arithmetic. And anyone who reads the record can confirm: 472,811 + 39,504 = 512,315, which is odd, which means tails.

---

## 12. Extensions and Variations

The protocol is intentionally minimal. The following extensions are compatible with the core protocol and can be adopted as needed:

- **Recurring ceremonies.** A standing ceremony definition that is instantiated repeatedly (e.g., "weekly team lunch picker"). Each instance is a separate ceremony with its own commitments and entropy.

- **Delegated commitment.** A party authorizes another party to commit on their behalf. The delegation must be recorded.

- **Observers.** Parties who receive the record and can verify it, but who do not commit or contribute entropy. Observers strengthen accountability by increasing the number of independent copies of the record.

- **Tiered trust.** Different entropy methods for different stakes. A casual office coin toss might use officiant-generated entropy; a draft order for a competitive league might require participant-contributed entropy combined with an external beacon.

---

## Appendix A: Glossary

| Term | Definition |
|------|-----------|
| Ceremony | A bounded protocol instance that produces a single verified random outcome. |
| Ceremony Identity | A unique identifier distinguishing this ceremony from all others; included in entropy seals to prevent replay. |
| Commitment | An irrevocable, authenticated statement by a party to accept the outcome. |
| Commitment Boundary | The moment between Phase 2 and Phase 3; the last point at which the ceremony may fail to proceed. |
| Commitment Mode | Whether the ceremony proceeds immediately upon reaching the required number of commitments, or waits for the deadline. |
| Entropy | Unpredictable input from which the outcome is derived. |
| Entropy Ordering Invariant | The guarantee that no outcome-relevant information is available to any party before all commitments are collected. |
| Initiator | The party who creates a ceremony by specifying its parameters. |
| Officiant | The party responsible for executing the protocol steps. |
| Outcome | The deterministic result of applying the derivation function to the combined entropy. |
| Modular Bias | Uneven outcome probabilities caused by mapping entropy onto an outcome space whose size does not evenly divide the entropy space. |
| Record | The ordered, tamper-evident log of all ceremony events. |
| Identity Mode | How participant identity is established: anonymous (opaque token), authenticated (external authority), or self-certified (cryptographic keypair). |
| Non-Repudiation | The property that a party cannot plausibly deny having committed; its strength depends on the identity mode. |
| Reveal Deadline | The point by which all participants must reveal their sealed entropy (Methods A and D). |
| Roster | The ordered list of (party identifier, public key) pairs, published before commitments begin (Mode 3 only). |
| Roster Acknowledgment | A party's signature over the roster, proving they saw who else was participating and chose to proceed (Mode 3 only). |
| Seal | A mechanism that binds a party to a value without revealing it. |

## Appendix B: Notation for Formal Analysis

For those who wish to reason about the protocol formally, the following notation may be useful.

Let *C* be a ceremony with parameters *P*, parties *{p_1, ..., p_n}*, and entropy contributions *{e_1, ..., e_n}*.

- **seal(e_i)** denotes the sealed form of *e_i* (e.g., *H(C, p_i, e_i)* in a cryptographic setting).
- **combine(e_1, ..., e_n)** denotes the combination function producing the ceremony's entropy *E*.
- **derive(P, E)** denotes the deterministic derivation of the outcome from the parameters and combined entropy.
- **record(C)** = *(event_1, event_2, ..., event_m)* is the ordered sequence of events.
- **verify(record(C))** is the predicate that all verification checks (Section 8) pass.

The core safety property can then be stated:

> For all parties *p_i* and for all moments *t* prior to the commitment boundary: the conditional distribution of **derive(P, combine(e_1, ..., e_n))** given the information available to *p_i* at time *t* matches the distribution specified by the ceremony parameters *P* (uniform for unweighted outcome types; weighted as declared for weighted selections).

This holds under Method A if at least one party's entropy is genuinely random and independent. It holds under Method B if the external source is independent of all parties' actions. It holds under Method D if either condition holds.
