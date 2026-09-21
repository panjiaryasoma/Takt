# Discovery Evaluation — Real-World Cases

**Version:** 1.0  
**Date:** 2026-09-21  
**Purpose:** Test whether the problem brief survives contact with real competition rules, calendar semantics, scheduling technology, document extraction constraints, and human-AI governance evidence.

## 1. Discovery question

Is there a real, repeated problem worth solving at the intersection of competition-rule understanding, eligibility/readiness checking, workload decomposition, calendar-aware capacity, feasible work allocation, and human-controlled recommendations?

## 2. Real competition cases

### Case A — Shipaton 2026
Shipaton exposes a named deadline with Pacific Time, geography restrictions, student-specific Next Gen conditions, different submission expectations for student entries, and category-specific evidence. Information is spread across FAQ, Next Gen, announcement, and submission guidance (`SRC-001`–`SRC-004`).

**Implication:** one URL may be insufficient. The source model must support multiple related pages and preserve where a field came from.

### Case B — Swift Student Challenge 2026
Apple's challenge has region-dependent minimum ages, student-status requirements, individual-only work, an offline-judged app playground, a ZIP size limit, and an exact deadline (`SRC-005`–`SRC-007`).

**Implication:** eligibility is conditional, not a single boolean scraped from a heading. Requirements can constrain architecture itself.

### Case C — Imagine Cup 2026
Imagine Cup requires enrolled students aged 18+, allows teams of one to four, specifies Microsoft AI-service usage, and asks for multiple submission artifacts (`SRC-008`).

**Implication:** task generation must distinguish product work from mandatory submission work. Required technology is a first-class field.

### Case D — HackMIT 2026
HackMIT combines age rules with an exception for MIT students and defines student status relative to the event period (`SRC-009`).

**Implication:** eligibility statements require predicates and exceptions. A naive keyword classifier is insufficient.

### Case E — GitHub Game Off 2025
The event announcement and jam page describe a fixed deadline, GitHub repository expectations and itch.io submission. The FAQ clarifies team-size behavior, while an organizer post later documents a missed-deadline exception (`SRC-010`–`SRC-013`).

**Implication:** source authority and freshness matter. A canonical report must preserve conflicts/exceptions instead of selecting a value solely by model confidence.

### Case F — GitLab AI Hackathon on Devpost
Official rules present submission/judging windows in Eastern Time and use legal age-of-majority language (`SRC-014`).

**Implication:** exact timezone preservation and normalized local display are required; age eligibility can depend on jurisdiction.

## 3. Platform evidence

Devpost's organizer guidance says eligibility should be clear before participants invest work, and rule pages should describe project requirements, submission assets, prizes, and winner selection (`SRC-015`, `SRC-016`). Its judging documentation shows that criteria are explicit inputs to judging (`SRC-017`).

**Conclusion:** the canonical competition report should include eligibility, deliverables, judging criteria, and submission requirements as core fields rather than optional prose.

## 4. Calendar and planning evidence

Google Calendar's FreeBusy API can return busy intervals without event-title content (`SRC-018`). Calendar recurrence is richer than copying visible events; Google Calendar and RFC 5545 define recurrence and exceptions (`SRC-019`, `SRC-020`).

OR-Tools examples show CP-SAT handling assignment, capacity, non-overlap, and task precedence (`SRC-021`, `SRC-022`).

Recent research supports the importance of student time management and timetable structure, but does not validate this specific product (`SRC-029`, `SRC-030`).

**Conclusion:** use calendar-aware capacity, not merely a weekly free-hour sum. Treat CP-SAT as a candidate-allocation engine, not an autonomous life scheduler.

## 5. Mixed-document discovery

PyMuPDF can extract native text and images independently; OCR is available for image-based text (`SRC-023`, `SRC-024`). PyMuPDF4LLM supports hybrid OCR and multiple OCR engines (`SRC-025`, `SRC-026`).

### Architectural conclusion

```text
PDF
├── FW1: native/structured extraction → Candidate Extraction Report A
└── FW2: visual/OCR extraction       → Candidate Extraction Report B

A + B → field-level reconciliation → Canonical Competition Report
```

Both candidate reports use the same schema. Reconciliation happens **after** extraction. A conflict remains a conflict until resolved by evidence or user review.

## 6. Human-AI boundary

NIST's AI RMF emphasizes reliability, transparency, explainability, privacy, and human oversight (`SRC-027`, `SRC-028`).

The product therefore must not turn a probabilistic extraction or optimization result into an unexplained instruction.

Preferred interaction:
- Recommended work window: Tue 19:00–21:00
- Why: 2-hour contiguous free block; task blocks integration; preserves 5-hour buffer
- Alternative: Wed 13:00–15:00
- user accepts, edits, or ignores.

Not: "You must work Tuesday at 7 PM."

## 7. Hypothesis evaluation

| Hypothesis | Evidence strength | Decision |
|---|---|---|
| Competition rules contain planning-critical structured fields | Strong | Keep |
| Requirements may be scattered or conditional | Strong | Keep multi-source/provenance model |
| Calendar-aware capacity is relevant | Moderate-to-strong | Keep |
| A deterministic feasibility engine is technically appropriate | Strong technical fit | Keep |
| Dual-path PDF extraction improves robustness for mixed documents | Strong technical rationale; product-level accuracy still to test | Keep and evaluate |
| Users need a final auto-generated timeline | Weak / conflicts with decision-support framing | Reject |
| Users need recommendations + alternatives + trade-offs | Plausible, not yet behaviorally validated | Keep as MVP hypothesis |
| Social teammate matching is needed | Unproven and scope-expanding | Exclude |
| Custom ML is necessary at launch | No | Reject for MVP |
| Monetization willingness is established | No | Validate separately |

## 8. Product decision after discovery

**GO, with narrowed framing.**

Proceed as a **calendar-aware competition decision-support system**.

Do not position the product as an autonomous agent, an AI project manager, a social network, or a final-schedule generator.

The defensible core is:

> Convert messy competition sources into a canonical, provenance-backed brief; evaluate it against real calendar constraints; generate feasible work options; explain recommendations and trade-offs; preserve human decision authority.

## 9. Discovery sources

- **SRC-001 — Shipaton 2026 FAQ** (Official organizer, quality: high)  
  Current competition FAQ with deadline, timezone, team and regional eligibility nuances.  
  https://www.shipaton.com/faq
- **SRC-002 — Shipaton 2026 Next Gen Award** (Official organizer, quality: high)  
  Student-specific eligibility, age, academic-email verification and alternate submission path.  
  https://www.shipaton.com/next-gen
- **SRC-003 — How to submit your app for Shipaton 2026** (Official organizer, quality: high)  
  Submission artifacts and category-specific evidence requirements.  
  https://www.shipaton.com/blog/how-to-submit-your-app-for-shipaton
- **SRC-004 — Announcing Shipaton 2026** (Official organizer, quality: high)  
  High-level event scope and award-category framing.  
  https://www.shipaton.com/blog/announcing-shipaton-2026
- **SRC-005 — Swift Student Challenge — Eligibility and Requirements** (Official organizer, quality: high)  
  Region-dependent age rules, student status, individual submission, offline-app constraints.  
  https://developer.apple.com/swift-student-challenge/eligibility/
- **SRC-006 — Swift Student Challenge 2026 Terms and Conditions** (Official legal terms, quality: high)  
  Exact deadline and legal eligibility conditions; stronger authority than summary copy.  
  https://developer.apple.com/swift-student-challenge/policy/
- **SRC-007 — Swift Student Challenge — Apply** (Official organizer, quality: high)  
  Submission window and preparation guidance.  
  https://developer.apple.com/swift-student-challenge/apply/
- **SRC-008 — Imagine Cup FAQ** (Official organizer, quality: high)  
  Student/age eligibility, team-size limits, required technology and submission artifacts.  
  https://imaginecup.microsoft.com/en-us/support/faq
- **SRC-009 — HackMIT 2026 FAQ** (Official organizer, quality: high)  
  Age and student-status conditions, MIT-specific exception, application date and team size.  
  https://hackmit.org/?lang=en
- **SRC-010 — GitHub Game Off 2025 Theme Announcement** (Official organizer, quality: high)  
  Deadline with timezone, public repository and submission workflow.  
  https://github.blog/company/github-game-off-2025-theme-announcement/
- **SRC-011 — GitHub Game Off 2025 — itch.io jam page** (Official event platform, quality: high)  
  Event window, submission platform and judging categories.  
  https://itch.io/jam/game-off-2025
- **SRC-012 — GitHub Game Off 2025 FAQ** (Organizer community FAQ, quality: medium-high)  
  Team-size and submission clarifications not fully represented in announcement copy.  
  https://itch.io/jam/game-off-2025/topic/5489423/frequently-asked-questions-faq
- **SRC-013 — Game Off 2025 missed-deadline notice** (Organizer community notice, quality: medium-high)  
  Real example of an organizer-published exception after the nominal deadline.  
  https://itch.io/jam/game-off-2025/topic/5604242/if-you-miss-the-submission-deadline
- **SRC-014 — GitLab AI Hackathon Official Rules** (Official rules via Devpost, quality: high)  
  Structured dates in a named timezone and age-of-majority eligibility language.  
  https://gitlab.devpost.com/rules
- **SRC-015 — Devpost — Setting eligibility requirements** (Platform documentation, quality: high)  
  Evidence that eligibility is a first-class competition field and should be checked before effort is spent.  
  https://help.devpost.com/article/143-setting-eligibility-requirements
- **SRC-016 — Devpost — Creating hackathon rules** (Platform documentation, quality: high)  
  Project requirements, submission assets, prizes and winner-selection information may be distributed across rule sections.  
  https://help.devpost.com/article/140-creating-hackathon-rules
- **SRC-017 — Devpost — Judging & public voting** (Platform documentation, quality: high)  
  Judging criteria are explicit decision-relevant fields and may be weighted or explained separately.  
  https://help.devpost.com/article/64-judging-public-voting
- **SRC-018 — Google Calendar API — FreeBusy query** (Official API documentation, quality: high)  
  Supports a privacy-reduced integration pattern using busy intervals instead of event titles.  
  https://developers.google.com/workspace/calendar/api/v3/reference/freebusy/query
- **SRC-019 — Google Calendar API — Events resource** (Official API documentation, quality: high)  
  Calendar events include recurrence semantics and event types that affect availability modeling.  
  https://developers.google.com/workspace/calendar/api/v3/reference/events
- **SRC-020 — RFC 5545 — iCalendar** (Internet standard, quality: high)  
  Canonical recurrence, exception and date-time semantics for calendar interoperability.  
  https://www.rfc-editor.org/info/rfc5545/
- **SRC-021 — OR-Tools — Employee Scheduling** (Official technical documentation, quality: high)  
  CP-SAT is suitable for hard scheduling constraints and preference-aware assignment.  
  https://developers.google.com/optimization/scheduling/employee_scheduling
- **SRC-022 — OR-Tools — Job Shop Scheduling** (Official technical documentation, quality: high)  
  Demonstrates precedence constraints and non-overlap scheduling relevant to task dependencies.  
  https://developers.google.com/optimization/scheduling/job_shop
- **SRC-023 — PyMuPDF — The Basics** (Official technical documentation, quality: high)  
  Native PDF text extraction and OCR entry points; image extraction is independently available.  
  https://pymupdf.readthedocs.io/en/latest/the-basics.html
- **SRC-024 — PyMuPDF — OCR Recipe** (Official technical documentation, quality: high)  
  OCR can target complete pages or image regions and is materially more expensive than native extraction.  
  https://pymupdf.readthedocs.io/en/latest/recipes-ocr.html
- **SRC-025 — PyMuPDF4LLM documentation** (Official technical documentation, quality: high)  
  Hybrid OCR behavior and structured/Markdown document extraction.  
  https://pymupdf.readthedocs.io/en/latest/pymupdf4llm/
- **SRC-026 — PyMuPDF4LLM OCR Plugins** (Official technical documentation, quality: high)  
  Supports Tesseract, RapidOCR, PaddleOCR and combined recognition/detection strategies.  
  https://pymupdf.readthedocs.io/en/latest/pymupdf4llm/ocr-plugins.html
- **SRC-027 — NIST AI Risk Management Framework** (Government framework, quality: high)  
  Supports reliability, accountability, transparency, privacy and human-centered AI risk management.  
  https://www.nist.gov/itl/ai-risk-management-framework
- **SRC-028 — NIST AIRC — Explainable and Interpretable** (Government framework, quality: high)  
  Supports explanations that let users understand and oversee AI-produced outputs.  
  https://airc.nist.gov/airmf-resources/airmf/3-sec-characteristics/
- **SRC-029 — 2026 Meta-analysis: time management and college learning outcomes** (Peer-reviewed systematic review, quality: high)  
  31-study meta-analysis (13,506 participants) reporting a moderate positive association between time management and learning outcomes.  
  https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2026.1700298/full
- **SRC-030 — Timetables, attendance and academic achievement in higher education** (Peer-reviewed research, quality: high)  
  Shows timetable structure affects attendance and study behavior, supporting calendar-aware rather than hours-only capacity modeling.  
  https://www.sciencedirect.com/science/article/pii/S0014292126002011
