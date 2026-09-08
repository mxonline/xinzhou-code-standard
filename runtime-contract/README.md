# Global Runtime Contract v1

`tools/runtime_contract.py` is the shared machine validator for the cross-project Runtime Contract.

Projects should keep their own business state machines and expose a small `runtime-contract.json` manifest. CI must pin this repository to an immutable merge SHA before invoking the validator.

Profiles:

- `canonical-v1`: native execution_id + state_revision + execution-aware events + evidence.
- `arthur-v2`: compatibility adapter for XinZhaoWrt schema v2, including firmware ledger seq/hash-link checks without inventing state_revision.

Validation never creates PASS. It verifies persisted state/event/evidence consistency only. Real Git, CI, device, local runtime, file, video/QA and external tool observations remain factual authority.

The `instances/video-factory-v1-production-first/` directory is a machine-readable mirror of the currently accepted Notion Video Factory Runtime revision 2. It makes the persisted Runtime Contract CI-verifiable, but it is not evidence that an inaccessible production video executor automatically writes these files after every Stage/Shot.
