# Quality Findings

Statuses are `open`, `in progress`, `closed`, `duplicate`, or `rejected`.
Closing a finding requires a change reference and verification evidence.

| ID | Severity | Unit | Status | Finding | Required resolution |
| --- | --- | --- | --- | --- | --- |
| Q-CODEC-001 | Medium | Q11 | Open | The embedded MP3 Huffman and synthesis-window tables do not record a reproducible extraction method. The Huffman table names ISO/IEC 11172-3, while the synthesis table names no source. | Record authoritative provenance and add a deterministic integrity or regeneration check that fails on accidental edits. |
| Q-ARCH-001 | Medium | Q00, Q02, Q04, Q10–Q19 | Open | Several handwritten source files combine thousands of production lines with large colocated test suites. Ogg and MP3 each exceed 30,000 total lines and 15,000 lines before the first test declaration. ADM XML exceeds 14,000 total lines and 9,000 before its first test. | Phase 4 must record a cohesion decision for each large handwritten file and split files when a narrower contract improves reviewability without obscuring invariants. |
| Q-ARCH-002 | Medium | Q14, Q15, Q16 | Open | `dsp/hrtf.zig` imports the shared partitioned convolver from `gui_ir_convolution.zig`. The imported module owns DSP processing, lock-free preparation queues, realtime publication, and no GUI behavior required by HRTF. Its name and placement reverse the intended DSP-to-GUI dependency. | Move or split the shared convolution and publication contract into the DSP layer, retain a compatible public alias if required, and verify HRTF, GUI IR, installed-package, and compatibility gates. |
| Q-ADM-001 | Medium | Q13 | Open | `adm_xml.Document.init` accepts an unbounded byte slice, performs separate full-document scans for each metadata category, and then performs nested rescans for duplicate declarations, references, cardinalities, and block sequences. The 1,792-test Debug group containing ADM took 47 minutes during the Phase 0 gate while remaining CPU-bound. | In Phase 3, establish explicit input and work limits, replace avoidable nested reparsing with a bounded validation strategy, add complexity regression coverage, and measure Debug and ReleaseSafe behavior on representative and adversarial documents. |
| Q-MEM-001 | Medium | Q04 | Closed | Framework VST3 component and controller objects hard-coded `page_allocator` for allocation and destruction. This preserved allocator compatibility in production but prevented deterministic failure injection for the owning object and processor-construction boundary. | Commit `8158b82d` stores allocator provenance, preserves the public ABI through allocator-injected internal creation, and adds outer and nested allocation-failure tests. The focused VST3 module gate passed 786/786 tests. |

No critical or high finding is open at the start of Phase 0. This statement is
an inventory status, not a conclusion about code that has not yet received its
assigned review.
