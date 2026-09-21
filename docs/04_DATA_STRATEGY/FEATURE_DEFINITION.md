# Feature Definition

**Version:** 1.0

## Principle
A feature is allowed only if it is available at the moment the system is expected to make the prediction or recommendation.

## Feature groups

### Competition-source features
Examples: days to deadline, mandatory deliverable count, required technology count, team-size bounds, source-conflict count, unresolved critical-field count.

### Calendar features
Examples: total available minutes, number of free blocks, maximum contiguous block, number of 90+ minute blocks, fixed commitment load, fragmentation ratio, daily capacity.

Aggregate free hours alone are insufficient because ten continuous hours and twenty 30-minute fragments are different planning states.

### Task features
Task type, mandatory/optional, dependency count/depth, required skill, deliverable association, min/likely/max estimate, and unblock value.

### User-configured planning features
Preferred focus block, maximum project hours/day, buffer target, fixed/flexible semantics, and explicitly selected work windows.

### Historical features, future phase
Median estimate-to-actual ratio, actual effort by task type, historical overrun frequency, and task-family calibration. Valid only after real labels exist.

## Availability stages
- `PRE_ANALYSIS`
- `POST_EXTRACTION`
- `POST_DECOMPOSITION`
- `POST_EXECUTION`

`POST_EXECUTION` features are forbidden inputs to pre-execution models.

## Leakage-sensitive examples
Do not use actual task hours, completion outcome, recommendation acceptance, final submission result, competition result, or any label-derived risk score as pre-execution predictors.

## Feature provenance
Each modeled feature should record name, source, availability stage, transformation, version, missing-value rule, unit, and permitted model uses.
