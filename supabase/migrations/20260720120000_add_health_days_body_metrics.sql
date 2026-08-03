-- Insight-engine pivot: the longitudinal digest needs body-scale metrics
-- beyond steps/sleep/RHR/HRV. Same contract as the existing columns —
-- the client computes one aggregate per local day on-device; raw HealthKit
-- samples never sync.

alter table public.health_days
  add column weight_kg          numeric(5,2),
  add column active_energy_kcal int,
  add column workout_minutes    int;
