"""Pure field-level reconciliation from candidate reports to CanonicalField."""

from __future__ import annotations

import json
from collections.abc import Iterable
from hashlib import sha256

from packages.contracts import (
    CandidateExtractionReport,
    CanonicalField,
    CanonicalFieldState,
    EvidenceSpan,
    SourceRecord,
)

from engine.reconciliation.models import (
    CandidateObservation,
    FieldReconciliationResult,
    ReconciliationInputError,
    ScopeDescriptor,
    ScopeRelation,
)
from engine.reconciliation.policy import (
    UnusableNormalizedValue,
    comparison_value,
    intersect_scopes,
    parse_authority,
    parse_freshness,
    parse_scope,
    scope_relation,
    source_supersedes,
)


def _stable_json(value: object) -> str:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        default=str,
    )


def _report_fingerprint(report: CandidateExtractionReport) -> str:
    payload = report.model_dump(mode="json")
    encoded = json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        default=str,
    ).encode("utf-8")
    return sha256(encoded).hexdigest()[:16]


def _observation_sort_key(observation: CandidateObservation) -> tuple[object, ...]:
    return (
        observation.source_id,
        observation.field.extraction_path.value,
        observation.field.field_name,
        tuple(sorted(observation.field.evidence_ids)),
        _stable_json(observation.effective_scope.as_mapping()),
        _stable_json(observation.field.normalized_value),
        _stable_json(observation.field.raw_value),
    )


def _candidate_sort_key(observation: CandidateObservation) -> tuple[object, ...]:
    return _observation_sort_key(observation)


def _evidence_ids(observations: Iterable[CandidateObservation]) -> list[str]:
    return sorted(
        {
            evidence.evidence_id
            for observation in observations
            for evidence in observation.evidence
        }
    )


def _candidates(observations: Iterable[CandidateObservation]):
    return [
        observation.field
        for observation in sorted(observations, key=_candidate_sort_key)
    ]


def collect_candidate_observations(
    reports: Iterable[CandidateExtractionReport],
    sources: Iterable[SourceRecord],
) -> tuple[CandidateObservation, ...]:
    """Validate source metadata, provenance linkage, and effective applicability."""

    source_by_id: dict[str, SourceRecord] = {}
    for source in sources:
        if source.source_id in source_by_id:
            raise ReconciliationInputError(
                f"duplicate SourceRecord source_id: {source.source_id!r}"
            )
        source_by_id[source.source_id] = source

    seen_report_keys: set[tuple[str, object, str]] = set()
    seen_evidence_ids: set[str] = set()
    parsed_source_metadata: dict[
        str,
        tuple[ScopeDescriptor, object, object],
    ] = {}
    observations: list[CandidateObservation] = []

    for report in reports:
        source = source_by_id.get(report.source_id)
        if source is None:
            raise ReconciliationInputError(
                f"candidate report references unknown source_id: {report.source_id!r}"
            )

        if source.source_id not in parsed_source_metadata:
            parsed_source_metadata[source.source_id] = (
                parse_scope(source.scope),
                parse_authority(source),
                parse_freshness(source),
            )
        source_scope, authority, freshness = parsed_source_metadata[source.source_id]

        report_key = (
            report.source_id,
            report.extraction_path,
            _report_fingerprint(report),
        )
        if report_key in seen_report_keys:
            raise ReconciliationInputError(
                "duplicate candidate report snapshot for source/path: "
                f"{report.source_id!r}, {report.extraction_path.value!r}"
            )
        seen_report_keys.add(report_key)

        evidence_by_id: dict[str, EvidenceSpan] = {}
        for evidence in report.evidence:
            if evidence.evidence_id in seen_evidence_ids:
                raise ReconciliationInputError(
                    "duplicate evidence_id across reconciliation input: "
                    f"{evidence.evidence_id!r}"
                )
            seen_evidence_ids.add(evidence.evidence_id)

            if evidence.source_id != report.source_id:
                raise ReconciliationInputError(
                    "evidence source_id must match candidate report source_id"
                )
            if evidence.extraction_path is not report.extraction_path:
                raise ReconciliationInputError(
                    "evidence extraction_path must match candidate report extraction_path"
                )
            evidence_by_id[evidence.evidence_id] = evidence

        for field in report.fields:
            if field.extraction_path is not report.extraction_path:
                raise ReconciliationInputError(
                    "candidate extraction_path must match candidate report extraction_path"
                )

            linked_evidence: list[EvidenceSpan] = []
            for evidence_id in field.evidence_ids:
                evidence = evidence_by_id.get(evidence_id)
                if evidence is None:
                    raise ReconciliationInputError(
                        f"candidate evidence_id does not exist in report: {evidence_id!r}"
                    )
                if evidence.field_name != field.field_name:
                    raise ReconciliationInputError(
                        "evidence field_name must match candidate field_name"
                    )
                linked_evidence.append(evidence)

            candidate_scope = parse_scope(field.scope)
            effective_scope = intersect_scopes(source_scope, candidate_scope,
            )
            if effective_scope is None:
                raise ReconciliationInputError(
                    "candidate scope is disZ›Ъ[ќњ›ЫH]ИЫЭ\ЩT™XЫЬ™ШЫЬH‚€
B‚€ШњЩ\ќ][ЫњЛ\[™
€Ш[™Y]SШњЩ\ќ][ЫЉ€ЫЭ\ЩWЪY\™\ЬќњЫЭ\ЩWЪY€™\ЬќЪЩ^O\™\ЬќЪЩ^K€ЫЭ\ЩWЬ™XЫЬ™\ЫЭ\ЩK€љY[YљY[€]љY[ЩO]\JЫЬќY
[љЩYЩ]љY[ЩKЩ^O[[X™H][N€][K™]љY[ЩWЪY
JK€ЫЭ\ЩWЬШЫЬO\ЫЭ\ЩWЬШЫЬK€Ш[™Y]WЬШЫЬOXШ[™Y]WЬШЫЬK€Y™™XЭ]™WЬШЫЬOYY™™XЭ]™WЬШЫЬK€]]Ьљ]OX]]Ьљ]K€њ™\Ъ™\ЬПYњ™\Ъ™\ЬЛ€
B€
B‚€™]\›€\JЫЬќY
ШњЩ\ќ][ЫњЛЩ^OWЫШњЩ\ќ][Ы—ЬЫЬќЪЩ^JJB‚‚™Y€Э[ќ™\љYљYY
€љY[Ы[YN€Э‹€ШњЩ\ќ][ЫњО€\VРШ[™Y]SШњЩ\ќ][Ы‹‹‹—K€
‹€\Ъ\О€\VЬЭ‹‹‹—KЉHO€љY[™XЫЫЪ[X][Ы”™\Э[‚€™]\›€љY[™XЫЫЪ[X][Ы”™\Э[
€Ш[›ЫљXШ[ЩљY[PШ[›ЫљXШ[љY[
€љY[Ы[YOYљY[Ы[YK€Э]OPШ[›ЫљXШ[љY[Э]K•S•‘T’Q’QQ€Ш[™Y]\ПWШШ[™Y]\КШњЩ\ќ][ЫњКK€]љY[ЩWЪYПWЩ]љY[ЩWЪYКШњЩ\ќ][ЫњКK€
K€™\ЫЫ][Ы—Ш\Ъ\ПX\Ъ\Л€Э\Ьќ[™ЧЬЫЭ\ЩWЪYПJ
K€
B‚‚™Y€ШЫЫ™›XЭ
€љY[Ы[YN€Э‹€ШњЩ\ќ][ЫњО€\VРШ[™Y]SШњЩ\ќ][Ы‹‹‹—K€
‹€Э\\њЩYYЬЫЭ\ЩWЪYО€\VЬЭ‹‹‹—HH

KЉHO€љY[™XЫЫЪ[X][Ы”™\Э[‚€™]\›€љY[™XЫЫЪ[X][Ы”™\Э[
€Ш[›ЫљXШ[ЩљY[PШ[›ЫљXШ[љY[
€љY[Ы[YOYљY[Ы[YK€Э]OPШ[›ЫљXШ[љY[Э]KђУУ‘“PХ€Ш[™Y]\ПWШШ[™Y]\КШњЩ\ќ][ЫњКK€]љY[ЩWЪYПWЩ]љY[ЩWЪYКШњЩ\ќ][ЫњКK€
K€™\ЫЫ][Ы—Ш\Ъ\ПJќ[њ™\ЫЫ™YX\XШX›KY\ШYЬ™Y[Y[ќ‹
K€Э\Ьќ[™ЧЬЫЭ\ЩWЪYПJ
K€Э\\њЩYYЬЫЭ\ЩWЪYП\Э\\њЩYYЬЫЭ\ЩWЪYЛ€
B‚‚™Y€ЬЪ[\WЭ\ШX›WЬ™\Э[
€љY[Ы[YN€Э‹€
‹€XЭ]™N€\VРШ[™Y]SШњЩ\ќ][Ы‹‹‹—K€[ЫШњЩ\ќ][ЫњО€\VРШ[™Y]SШњЩ\ќ][Ы‹‹‹—K€Э\\њЩYYЬЫЭ\ЩWЪYО€\VЬЭ‹‹‹—KЉHO€љY[™XЫЫЪ[X][Ы”™\Э[‚€™\™\Щ[ќ]]™HHZ[ЉXЭ]™KЩ^OWЫШњЩ\ќ][Ы—ЬЫЬќЪЩ^JB€ЫЫ\\™YHЫЫ\\љ\ЫЫ—Э[YJљY[Ы[YK™\™\Щ[ќ]]™K™љY[››Ь›X[^™YЭ[YJB€Э\Ьќ[™ЧЬЫЭ\ЩWЪYИH\JЫЬќY
Ъ][KњЫЭ\ЩWЪY›Ь€][H[€XЭ]™_JJB€Э]HH
€Ш[›ЫљXШ[љY[Э]K•‘T’Q’QQ€Y€[ЉЭ\Ьќ[™ЧЬЫЭ\ЩWЪYКHЏH‚€[ЩHШ[›ЫљXШ[љY[Э]K”ТS‘УWФУХTђСB€
B€\Ъ\ИH
€YЬ™Y[Y[ќћЫ[ЉЭ\Ьќ[™ЧЬЫЭ\ЩWЪYК_KZ[™\[™[ќ\ЫЭ\ЩH‹
B€Y€Э\\њЩYYЬЫЭ\ЩWЪYО‚€\Ъ\И
ПH
™]\›Z[љ\ЭXЛ\Э\\њЩ\ЬЪ[Ы€‹
B‚€™]\›€љY[™XЫЫЪ[X][Ы”™\Э[
€Ш[›ЫљXШ[ЩљY[PШ[›ЫљXШ[љY[
€љY[Ы[YOYљY[Ы[YK€Э]O\Э]K€[YO\™\™\Щ[ќ]]™K™љY[њ]ЧЭ[YK€›Ь›X[^™YЭ[YOXЫЫ\\™YШ[›ЫљXШ[€Ш[™Y]\ПWШШ[™Y]\К[ЫШњЩ\ќ][ЫњКK€]љY[ЩWЪYПWЩ]љY[ЩWЪYК[ЫШњЩ\ќ][ЫњКK€
K€™\ЫЫ][Ы—Ш\Ъ\ПX\Ъ\Л€Э\Ьќ[™ЧЬЫЭ\ЩWЪYП\Э\Ьќ[™ЧЬЫЭ\ЩWЪYЛ€Э\\њЩYYЬЫЭ\ЩWЪYП\Э\\њЩYYЬЫЭ\ЩWЪYЛ€
B‚‚™Y€ЬШЫЬYЬ™\Э[
€љY[Ы[YN€Э‹€
‹€XЭ]™N€\VРШ[™Y]SШњЩ\ќ][Ы‹‹‹—K€[ЫШњЩ\ќ][ЫњО€\VРШ[™Y]SШњЩ\ќ][Ы‹‹‹—K€Э\\њЩYYЬЫЭ\ЩWЪYО€\VЬЭ‹‹‹—KЉHO€љY[™XЫЫЪ[X][Ы”™\Э[‚€Ь›Э\О€XЭВ€\VЭ\VЬЭ€›Ы™KЭ€›Ы™KЭ€›Ы™WKЭ—K€\ЭРШ[™Y]SШњЩ\ќ][Ы—K€HHЯB€ШЫЬ\О€XЭВ€\VЭ\VЬЭ€›Ы™KЭ€›Ы™KЭ€›Ы™WKЭ—KШЫЬQ\ШЬљ\Ь‚€HHЯB‚€›Ь€ШњЩ\ќ][Ы€[€XЭ]™N‚€ШЫЬHHШњЩ\ќ][Ы‹™Y™™XЭ]™WЬШЫЬB€ЫЫ\\™YHЫЫ\\љ\ЫЫ—Э[YJљY[Ы[YKШњЩ\ќ][Ы‹™љY[››Ь›X[^™YЭ[YJB€Щ^HH
ШЫЬKљЩ^KЫЫ\\™YљЩ^JB€Ь›Э\ЛњЩ]Y][
Щ^KЧJK\[™
ШњЩ\ќ][ЫЉB€ШЫЬ\ЦЪЩ^WHHШЫЬB‚€]ЧЭ\љX[ќО€\ЭЩXЭЬЭ‹Шљ™XЭWHHЧB€›Ь›X[^™YЭ\љX[ќО€\ЭЩXЭЬЭ‹Шљ™XЭWHHЧB€Э\ЬќШЫЭ[ќО€\ЭЪ[ќHHЧB€Э\Ьќ[™ЧЬЫЭ\Щ\О€Щ]ЬЭ—HHЩ]

B‚€›Ь€Щ^H[€ЫЬќY
Ь›Э\ЛЩ^O[[X™H][N€
ЬЭX›WЪњЫЫЉ][VМJK][VМWJJN‚€Ь›Э\H\JЫЬќY
Ь›Э\ЦЪЩ^WKЩ^OWЫШњЩ\ќ][Ы—ЬЫЬќЪЩ^JJB€™\™\Щ[ќ]]™HHЬ›Э\МB€ЫЫ\\™YHЫЫ\\љ\ЫЫ—Э[YJљY[Ы[YK™\™\Щ[ќ]]™K™љY[››Ь›X[^™YЭ[YJB€ШЫЬWЫX\[™ИHШЫЬ\ЦЪЩ^WK\ЧЫX\[™К
B€Ь›Э\ЬЫЭ\Щ\ИHЫЬќY
Ъ][KњЫЭ\ЩWЪY›Ь€][H[€Ь›Э\JB€Э\ЬќШЫЭ[ќЛ\[™
[ЉЬ›Э\ЬЫЭ\Щ\КJB€Э\Ьќ[™ЧЬЫЭ\Щ\Лќ\]JЬ›Э\ЬЫЭ\Щ\КB€]ЧЭ\љX[ќЛ\[™
€В€њШЫЬHЋ€ШЫЬWЫX\[™Л€ќ[YHЋ€™\™\Щ[ќ]]™K™љY[њ]ЧЭ[YK€B€
B€›Ь›X[^™YЭ\љX[ќЛ\[™
€В€њШЫЬHЋ€ШЫЬWЫX\[™Л€ќ[YHЋ€ЫЫ\\™YШ[›ЫљXШ[€B€
B‚€Э]HH
€Ш[›ЫљXШ[љY[Э]K•‘T’Q’QQ€Y€Э\ЬќШЫЭ[ќИ[™[
ЫЭ[ќЏH€›Ь€ЫЭ[ќ[€Э\ЬќШЫЭ[ќКB€[ЩHШ[›ЫљXШ[љY[Э]K”ТS‘УWФУХTђСB€
B€\Ъ\ИH
њШЫЬY]\љX[ќИ‹
B€Y€Э\\њЩYYЬЫЭ\ЩWЪYО‚€\Ъ\И
ПH
™]\›Z[љ\ЭXЛ\Э\\њЩ\ЬЪ[Ы€‹
B‚€™]\›€љY[™XЫЫЪ[X][Ы”™\Э[
€Ш[›ЫљXШ[ЩљY[PШ[›ЫљXШ[љY[
€љY[Ы[YOYљY[Ы[YK€Э]O\Э]K€[YO^Иќ\љX[ќИЋ€]ЧЭ\љX[ќЯK€›Ь›X[^™YЭ[YO^Иќ\љX[ќИЋ€›Ь›X[^™YЭ\љX[ќЯK€Ш[™Y]\ПWШШ[™Y]\К[ЫШњЩ\ќ][ЫњКK€]љY[ЩWЪYПWЩ]љY[ЩWЪYК[ЫШњЩ\ќ][ЫњКK€
K€™\ЫЫ][Ы—Ш\Ъ\ПX\Ъ\Л€Э\Ьќ[™ЧЬЫЭ\ЩWЪYП]\JЫЬќY
Э\Ьќ[™ЧЬЫЭ\Щ\КJK€Э\\њЩYYЬЫЭ\ЩWЪYП\Э\\њЩYYЬЫЭ\ЩWЪYЛ€
B‚‚™Y€Ъ\ЧЩ\Ъ›Ъ[ќЬZ\ЉШњЩ\ќ][ЫњО€\VРШ[™Y]SШњЩ\ќ][Ы‹‹‹—JHO€›ЫЫ‚€›Ь€YќЪ[™^Yќ[€[ќ[Y\]JШњЩ\ќ][ЫњКN‚€›Ь€љYЪ[€ШњЩ\ќ][ЫњЦЫYќЪ[™^
ИH—N‚€Y€
€ШЫЬWЬ™[][ЫЉYќ™Y™™XЭ]™WЬШЫЬKљYЪ™Y™™XЭ]™WЬШЫЬJB€\ИШЫЬT™[][Ы‹‘TТ“ТS•€
N‚€™]\›€ќYB€™]\›€[ЩB‚‚™Y€™XЫЫЪ[WЩљY[
€љY[Ы[YN€Э‹€™\ЬќО€]\X›VРШ[™Y]Q^XЭ[Ы”™\ЬќK€ЫЭ\Щ\О€]\X›VФЫЭ\ЩT™XЫЬ™KЉHO€љY[™XЫЫЪ[X][Ы”™\Э[‚€€€”™XЫЫЪ[HЫ™HљY[Ъ[H™]Z[љ[™И]™\ћHШ[™Y]KЩ]љY[ЩH™Y™\™[ЩK€€€‚‚€[ЫШњЩ\ќ][ЫњИHЫЫXЭШШ[™Y]WЫШњЩ\ќ][ЫњК™\ЬќЛЫЭ\Щ\КB€ШњЩ\ќ][ЫњИH\J€][H›Ь€][H[€[ЫШњЩ\ќ][ЫњИY€][K™љY[™љY[Ы[YHOHљY[Ы[YB€
B€Y€›ЭШњЩ\ќ][ЫњО‚€™]\›€љY[™XЫЫЪ[X][Ы”™\Э[
€Ш[›ЫљXШ[ЩљY[PШ[›ЫљXШ[љY[
€љY[Ы[YOYљY[Ы[YK€Э]OPШ[›ЫљXШ[љY[Э]K“RTФТS‘Л€
K€™\ЫЫ][Ы—Ш\Ъ\ПJ››ЛXШ[™Y]H‹
K€Э\Ьќ[™ЧЬЫЭ\ЩWЪYПJ
K€
B‚€ЫЫ\\љ\ЫЫњО€\ЭЬЭ—HHЧB€›Ь€ШњЩ\ќ][Ы€[€ШњЩ\ќ][ЫњО‚€Y€›ЭШњЩ\ќ][Ы‹]]Ьљ]KљЫ›ЭЫЋ‚€™]\›€Э[ќ™\љYљYY
€љY[Ы[YK€ШњЩ\ќ][ЫњЛ€\Ъ\ПJ]]Ьљ]K][љЫ›ЭЫ€‹
K€
B€Y€›ЭШњЩ\ќ][Ы‹™њ™\Ъ™\ЬЛљЫ›ЭЫЋ‚€™]\›€Э[ќ™\љYљYY
€љY[Ы[YK€ШњЩ\ќ][ЫњЛ€\Ъ\ПJ™њ™\Ъ™\ЬЛ][љЫ›ЭЫ€‹
K€
B€Y€›ЭШњЩ\ќ][Ы‹™Y™™XЭ]™WЬШЫЬKљЫ›ЭЫЋ‚€™]\›€Э[ќ™\љYљYY
€љY[Ы[YK€ШњЩ\ќ][ЫњЛ€\Ъ\ПJњШЫЬK][љЫ›ЭЫ€‹
K€
B€Y€ШњЩ\ќ][Ы‹™љY[њ]ЧЭ[YH\И›Ы™N‚€™]\›€Э[ќ™\љYљYY
€љY[Ы[YK€ШњЩ\ќ][ЫњЛ€\Ъ\ПJњ]Л][YK][ќ\ШX›H‹
K€
B€ћN‚€ЫЫ\\љ\ЫЫњЛ\[™
€ЫЫ\\љ\ЫЫ—Э[YJљY[Ы[YKШњЩ\ќ][Ы‹™љY[››Ь›X[^™YЭ[YJKљЩ^B€
B€^Щ\[ќ\ШX›S›Ь›X[^™Y[YN‚€™]\›€Э[ќ™\љYљYY
€љY[Ы[YK€ШњЩ\ќ][ЫњЛ€\Ъ\ПJ››Ь›X[^™Y][YK][ќ\ШX›H‹
K€
B‚€Э\\њЩYYЪ[™^\О€Щ]Ъ[ќHHЩ]

B€Э\\њЩ\ЬЪ[Ы—Ш\Ъ\О€\ЭЬЭ—HHЧB€›Ь€YќЪ[™^Yќ[€[ќ[Y\]JШњЩ\ќ][ЫњКN‚€›Ь€љYЪЪ[™^[€[™ЩJYќЪ[™^
ИK[ЉШњЩ\ќ][ЫњКJN‚€љYЪHШњЩ\ќ][ЫњЦЬљYЪЪ[™^B€Y€ЫЫ\\љ\ЫЫњЦЫYќЪ[™^HOHЫЫ\\љ\ЫЫњЦЬљYЪЪ[™^N‚€ЫЫќ[ќYB€™[][Ы€HШЫЬWЬ™[][ЫЉYќ™Y™™XЭ]™WЬШЫЬKљYЪ™Y™™XЭ]™WЬШЫЬJB€Y€™[][Ы€›Э[€ФШЫЬT™[][Ы‹”РSQKШЫЬT™[][Ы‹“Х‘T“TЯN‚€ЫЫќ[ќYB‚€YќЫЭ™\—ЬљYЪHЫЭ\ЩWЬЭ\\њЩY\КYќљYЪљY[Ы[YOYљY[Ы[YJB€љYЪЫЭ™\—ЫYќHЫЭ\ЩWЬЭ\\њЩY\КљYЪYќљY[Ы[YOYљY[Ы[YJB€Y€YќЫЭ™\—ЬљYЪOHљYЪЫЭ™\—ЫYќ‚€ЫЫќ[ќYB€Y€YќЫЭ™\—ЬљYЪ‚€Э\\њЩYYЪ[™^\ЛY
љYЪЪ[™^
B€Э\\њЩ\ЬЪ[Ы—Ш\Ъ\Л\[™
€ћЫYќњЫЭ\ЩWЪYOћЬљYЪњЫЭ\ЩWЪYHЉB€[ЩN‚€Э\\њЩYYЪ[™^\ЛY
YќЪ[™^
B€Э\\њЩ\ЬЪ[Ы—Ш\Ъ\Л\[™
€ћЬљYЪњЫЭ\ЩWЪYOћЫYќњЫЭ\ЩWЪYHЉB‚€XЭ]™WЪ[™^\ИH\J€[™^›Ь€[™^[€[™ЩJ[ЉШњЩ\ќ][ЫњКJHY€[™^›Э[€Э\\њЩYYЪ[™^\В€
B€XЭ]™HH\JШњЩ\ќ][ЫњЦЪ[™^H›Ь€[™^[€XЭ]™WЪ[™^\КB€Y€›ЭXЭ]™N‚€™]\›€Э[ќ™\љYљYY
€љY[Ы[YK€ШњЩ\ќ][ЫњЛ€\Ъ\ПJњЭ\\њЩ\ЬЪ[Ы‹Y[[Z[]YX[XШ[™Y]\И‹
K€
B‚€XЭ]™WЪЩ^\ИHШЫЫ\\љ\ЫЫњЦЪ[™^H›Ь€[™^[€XЭ]™WЪ[™^\ЯB€Э\\њЩYYЬЫЭ\ЩWЪYИH\J€ЫЬќY
ЫШњЩ\ќ][ЫњЦЪ[™^KњЫЭ\ЩWЪY›Ь€[™^[€Э\\њЩYYЪ[™^\ЯJB€
B‚€Y€[ЉXЭ]™WЪЩ^\КHOHN‚€Y€Ъ\ЧЩ\Ъ›Ъ[ќЬZ\ЉXЭ]™JN‚€™]\›€ЬШЫЬYЬ™\Э[
€љY[Ы[YK€XЭ]™OXXЭ]™K€[ЫШњЩ\ќ][ЫњП[ШњЩ\ќ][ЫњЛ€Э\\њЩYYЬЫЭ\ЩWЪYП\Э\\њЩYYЬЫЭ\ЩWЪYЛ€
B‚€™\Э[HЬЪ[\WЭ\ШX›WЬ™\Э[
€љY[Ы[YK€XЭ]™OXXЭ]™K€[ЫШњЩ\ќ][ЫњП[ШњЩ\ќ][ЫњЛ€Э\\њЩYYЬЫЭ\ЩWЪYП\Э\\њЩYYЬЫЭ\ЩWЪYЛ€
B€Y€Э\\њЩ\ЬЪ[Ы—Ш\Ъ\О‚€™]\›€љY[™XЫЫЪ[X][Ы”™\Э[
€Ш[›ЫљXШ[ЩљY[\™\Э[Ш[›ЫљXШ[ЩљY[€™\ЫЫ][Ы—Ш\Ъ\П\™\Э[њ™\ЫЫ][Ы—Ш\Ъ\В€
И\J€њЭ\\њЩY\ОћЪ][_H€›Ь€][H[€ЫЬќY
Щ]
Э\\њЩ\ЬЪ[Ы—Ш\Ъ\КJJK€Э\Ьќ[™ЧЬЫЭ\ЩWЪYП\™\Э[њЭ\Ьќ[™ЧЬЫЭ\ЩWЪYЛ€Э\\њЩYYЬЫЭ\ЩWЪYП\™\Э[њЭ\\њЩYYЬЫЭ\ЩWЪYЛ€
B€™]\›€™\Э[‚€›Ь€XЭ]™WЬЬЪ][Ы‹YќЪ[™^[€[ќ[Y\]JXЭ]™WЪ[™^\КN‚€›Ь€љYЪЪ[™^[€XЭ]™WЪ[™^\ЦШXЭ]™WЬЬЪ][Ы€
ИH—N‚€Y€ЫЫ\\љ\ЫЫњЦЫYќЪ[™^HOHЫЫ\\љ\ЫЫњЦЬљYЪЪ[™^N‚€ЫЫќ[ќYB€™[][Ы€HШЫЬWЬ™[][ЫЉ€ШњЩ\ќ][ЫњЦЫYќЪ[™^K™Y™™XЭ]™WЬШЫЬK€ШњЩ\ќ][ЫњЦЬљYЪЪ[™^K™Y™™XЭ]™WЬШЫЬK€
B€Y€™[][Ы€[€ФШЫЬT™[][Ы‹”РSQKШЫЬT™[][Ы‹“Х‘T“TЯN‚€™]\›€ШЫЫ™›XЭ
€љY[Ы[YK€ШњЩ\ќ][ЫњЛ€Э\\њЩYYЬЫЭ\ЩWЪYП\Э\\њЩYYЬЫЭ\ЩWЪYЛ€
B€Y€™[][Ы€\ИШЫЬT™[][Ы‹•S’У“ХУЋ‚€™]\›€Э[ќ™\љYљYY
€љY[Ы[YK€ШњЩ\ќ][ЫњЛ€\Ъ\ПJњШЫЬK\™[][Ы‹][љЫ›ЭЫ€‹
K€
B‚€™]\›€ЬШЫЬYЬ™\Э[
€љY[Ы[YK€XЭ]™OXXЭ]™K€[ЫШњЩ\ќ][ЫњП[ШњЩ\ќ][ЫњЛ€Э\\њЩYYЬЫЭ\ЩWЪYП\Э\\њЩYYЬЫЭ\ЩWЪYЛ€
B