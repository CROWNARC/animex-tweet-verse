-- Fix admin_keys RLS policy for updating
DROP POLICY IF EXISTS "Anyone can update admin keys" ON public.admin_keys;
CREATE POLICY "Users can update admin keys for redemption" ON public.admin_keys
FOR UPDATE USING (true);

-- Set posts to auto-approve by default
ALTER TABLE public.posts ALTER COLUMN status SET DEFAULT 'approved';

-- Create polls table for voting feature
CREATE TABLE public.polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  ends_at TIMESTAMP WITH TIME ZONE,
  total_votes INTEGER DEFAULT 0
);

-- Create poll options table
CREATE TABLE public.poll_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID REFERENCES public.polls(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  image_url TEXT,
  vote_count INTEGER DEFAULT 0,
  option_order INTEGER NOT NULL
);

-- Create poll votes table
CREATE TABLE public.poll_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID REFERENCES public.polls(id) ON DELETE CASCADE,
  option_id UUID REFERENCES public.poll_options(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(poll_id, user_id)
);

-- Enable RLS on poll tables
ALTER TABLE public.polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_votes ENABLE ROW LEVEL SECURITY;

-- RLS policies for polls
CREATE POLICY "Anyone can view polls" ON public.polls FOR SELECT USING (true);
CREATE POLICY "Users can create polls" ON public.polls FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update their own polls" ON public.polls FOR UPDATE USING (
  post_id IN (SELECT id FROM public.posts WHERE user_id = (auth.uid())::text)
);

-- RLS policies for poll options
CREATE POLICY "Anyone can view poll options" ON public.poll_options FOR SELECT USING (true);
CREATE POLICY "Users can create poll options" ON public.poll_options FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update their own poll options" ON public.poll_options FOR UPDATE USING (
  poll_id IN (SELECT id FROM public.polls WHERE post_id IN (SELECT id FROM public.posts WHERE user_id = (auth.uid())::text))
);

-- RLS policies for poll votes
CREATE POLICY "Anyone can view poll votes" ON public.poll_votes FOR SELECT USING (true);
CREATE POLICY "Users can vote on polls" ON public.poll_votes FOR INSERT WITH CHECK ((auth.uid())::text = user_id);
CREATE POLICY "Users can update their own votes" ON public.poll_votes FOR UPDATE USING ((auth.uid())::text = user_id);
CREATE POLICY "Users can delete their own votes" ON public.poll_votes FOR DELETE USING ((auth.uid())::text = user_id);

-- Function to update poll vote counts
CREATE OR REPLACE FUNCTION update_poll_counts()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Update option vote count
    UPDATE public.poll_options 
    SET vote_count = vote_count + 1 
    WHERE id = NEW.option_id;
    
    -- Update total poll votes
    UPDATE public.polls 
    SET total_votes = total_votes + 1 
    WHERE id = NEW.poll_id;
    
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    -- Update option vote count
    UPDATE public.poll_options 
    SET vote_count = vote_count - 1 
    WHERE id = OLD.option_id;
    
    -- Update total poll votes
    UPDATE public.polls 
    SET total_votes = total_votes - 1 
    WHERE id = OLD.poll_id;
    
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for poll vote counting
CREATE TRIGGER update_poll_vote_counts
  AFTER INSERT OR DELETE ON public.poll_votes
  FOR EACH ROW
  EXECUTE FUNCTION update_poll_counts();