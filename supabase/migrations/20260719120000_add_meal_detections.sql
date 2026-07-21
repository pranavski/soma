-- Raw object-detection output for photo-logged meals (v1.1).
-- parse-meal's photo branch runs the image through a hosted detection
-- model (Roboflow) before handing the labels to Claude; this column keeps
-- the model's raw output — labels, confidences, boxes, model id — on the
-- meal row for auditing, threshold tuning, and comparing against the
-- future on-device (CoreML) path.
--
-- jsonb rather than columns: the shape belongs to whichever detection
-- model is configured and may change when the model is swapped. Nothing
-- queries inside it yet, so no index.

alter table public.meals
  add column detections jsonb;
