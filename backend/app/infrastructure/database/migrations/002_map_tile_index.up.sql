CREATE INDEX IF NOT EXISTS reports_final_position_geometry_gist
ON nowave.reports
USING gist ((final_position::geometry));
