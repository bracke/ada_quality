# Domain model

Strong enumerations represent 33 indicators, execution status, compliance, severity, value kind, assessment status, and tool status. Measurements are discriminated Boolean, integer, decimal basis-point, text, enum, or unavailable values. Assessments own ordered results and concrete tool executions. `Is_Valid` and `Is_Publishable` enforce terminal completeness and uniqueness.
