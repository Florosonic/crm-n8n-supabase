CREATE OR REPLACE FUNCTION public.mark_ping_completed(p_ping_id uuid, p_notes text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE pings
    SET is_completed = TRUE,
        completed_at = NOW(),
        notes = COALESCE(p_notes, 'Выполнено вручную')
    WHERE id = p_ping_id;
    
    RETURN FOUND;
END;
$function$
