-- macros: extend meals + meal_items with protein/carbs/fat/fiber ranges.
-- Meal-level and item-level both use low/high ranges to stay symmetric
-- with the existing calorie-range design (single-value item macros would
-- imply a certainty we don't have from a voice transcript).

alter table public.meals
  add column protein_g_low  int,
  add column protein_g_high int,
  add column carbs_g_low    int,
  add column carbs_g_high   int,
  add column fat_g_low      int,
  add column fat_g_high     int,
  add column fiber_g_low    int,
  add column fiber_g_high   int;

alter table public.meals
  add constraint meals_protein_range_ok
    check (protein_g_high is null or protein_g_low is null or protein_g_high >= protein_g_low),
  add constraint meals_carbs_range_ok
    check (carbs_g_high   is null or carbs_g_low   is null or carbs_g_high   >= carbs_g_low),
  add constraint meals_fat_range_ok
    check (fat_g_high     is null or fat_g_low     is null or fat_g_high     >= fat_g_low),
  add constraint meals_fiber_range_ok
    check (fiber_g_high   is null or fiber_g_low   is null or fiber_g_high   >= fiber_g_low);

alter table public.meal_items
  add column protein_g_low  int,
  add column protein_g_high int,
  add column carbs_g_low    int,
  add column carbs_g_high   int,
  add column fat_g_low      int,
  add column fat_g_high     int,
  add column fiber_g_low    int,
  add column fiber_g_high   int;

alter table public.meal_items
  add constraint meal_items_protein_range_ok
    check (protein_g_high is null or protein_g_low is null or protein_g_high >= protein_g_low),
  add constraint meal_items_carbs_range_ok
    check (carbs_g_high   is null or carbs_g_low   is null or carbs_g_high   >= carbs_g_low),
  add constraint meal_items_fat_range_ok
    check (fat_g_high     is null or fat_g_low     is null or fat_g_high     >= fat_g_low),
  add constraint meal_items_fiber_range_ok
    check (fiber_g_high   is null or fiber_g_low   is null or fiber_g_high   >= fiber_g_low);
