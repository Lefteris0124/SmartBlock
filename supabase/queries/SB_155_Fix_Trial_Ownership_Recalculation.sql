BEGIN;

-- Avoid a PL/pgSQL record variable shadowing the table alias in the aggregate.
CREATE OR REPLACE FUNCTION public.recalculate_property_area_shares(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    active_count integer;
    incomplete_count integer;
    declared_apartments integer;
    expected_apartments integer;
    total_area numeric;
    allocated numeric := 0;
    row_number integer := 0;
    share_row record;
    calculated_share numeric(7, 4);
BEGIN
    SELECT p.total_apartments INTO expected_apartments
    FROM public.properties AS p WHERE p.id = p_property_id;

    SELECT COUNT(*)::integer,
           COUNT(*) FILTER (
               WHERE owner_row.apartment_count IS NULL
                  OR owner_row.area_sqm IS NULL
                  OR owner_row.title_deed_photo_path IS NULL
                  OR owner_row.area_declaration_confirmed_at IS NULL
           )::integer,
           COALESCE(SUM(owner_row.apartment_count), 0)::integer,
           COALESCE(SUM(owner_row.area_sqm), 0)
    INTO active_count, incomplete_count, declared_apartments, total_area
    FROM public.property_owners AS owner_row
    WHERE owner_row.property_id = p_property_id
      AND owner_row.ownership_status = 'active';

    IF active_count = 0 OR incomplete_count > 0 OR total_area <= 0 THEN
        RETURN;
    END IF;
    IF expected_apartments IS NOT NULL
       AND declared_apartments <> expected_apartments THEN
        RETURN;
    END IF;

    FOR share_row IN
        SELECT id, area_sqm
        FROM public.property_owners
        WHERE property_id = p_property_id AND ownership_status = 'active'
        ORDER BY id
    LOOP
        row_number := row_number + 1;
        IF row_number = active_count THEN
            calculated_share := 100.0000 - allocated;
        ELSE
            calculated_share := round(share_row.area_sqm * 100.0 / total_area, 4);
            allocated := allocated + calculated_share;
        END IF;
        UPDATE public.property_owners
        SET ownership_percentage = calculated_share
        WHERE id = share_row.id
          AND ownership_percentage IS DISTINCT FROM calculated_share;
    END LOOP;
END;
$function$;

COMMIT;

