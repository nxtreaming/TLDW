-- Migration: Fix function overloading issue for update_video_analysis_secure
-- Problem: PostgREST can't resolve between two function signatures (PGRST203 error)
-- Solution: Drop all versions and recreate only the needed 4-parameter version

-- Drop ALL overloaded versions (must specify exact signatures)
DROP FUNCTION IF EXISTS public.update_video_analysis_secure(text, uuid, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.update_video_analysis_secure(text, uuid, jsonb, jsonb, jsonb, jsonb, text);

-- Recreate the single correct version (4 parameters)
CREATE OR REPLACE FUNCTION public.update_video_analysis_secure(
    p_youtube_id text,
    p_user_id uuid,
    p_summary jsonb DEFAULT NULL,
    p_suggested_questions jsonb DEFAULT NULL
)
RETURNS TABLE (success boolean, video_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_video_id uuid;
    v_created_by uuid;
BEGIN
    -- Get video and check ownership
    SELECT id, created_by INTO v_video_id, v_created_by
    FROM public.video_analyses
    WHERE youtube_id = p_youtube_id;

    -- Video doesn't exist
    IF v_video_id IS NULL THEN
        RETURN QUERY SELECT false::boolean, NULL::uuid;
        RETURN;
    END IF;

    -- Ownership check:
    -- 1. If created_by is NULL (anonymous creation), any authenticated user can update
    -- 2. If created_by matches p_user_id, owner can update
    -- 3. Otherwise, reject the update
    IF v_created_by IS NOT NULL AND v_created_by != p_user_id THEN
        RETURN QUERY SELECT false::boolean, v_video_id;
        RETURN;
    END IF;

    -- Perform the update
    UPDATE public.video_analyses SET
        summary = COALESCE(p_summary, summary),
        suggested_questions = COALESCE(p_suggested_questions, suggested_questions),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_video_id;

    RETURN QUERY SELECT true::boolean, v_video_id;
END;
$$;

-- Re-grant permissions
GRANT EXECUTE ON FUNCTION public.update_video_analysis_secure TO authenticated;
