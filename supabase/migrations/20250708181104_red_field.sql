/*
  # Content Moderation System

  1. New Tables
    - `moderation_queue` - Posts/comments pending review
    - `moderation_actions` - Log of moderation actions taken
    - `content_warnings` - Content warning labels
    - `auto_moderation_rules` - Automated moderation rules

  2. Enhanced Security
    - Automated content filtering
    - Moderation workflow
    - Content warning system
*/

-- Create moderation queue table
CREATE TABLE IF NOT EXISTS moderation_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_type TEXT NOT NULL, -- 'post', 'comment'
  content_id UUID NOT NULL,
  reported_by TEXT,
  reason TEXT,
  priority INTEGER DEFAULT 1, -- 1=low, 2=medium, 3=high, 4=urgent
  status TEXT DEFAULT 'pending', -- 'pending', 'reviewing', 'resolved', 'dismissed'
  assigned_to TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create moderation actions table
CREATE TABLE IF NOT EXISTS moderation_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  moderator_id TEXT NOT NULL,
  content_type TEXT NOT NULL,
  content_id UUID NOT NULL,
  action_type TEXT NOT NULL, -- 'approve', 'reject', 'warn', 'remove', 'ban_user'
  reason TEXT,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create content warnings table
CREATE TABLE IF NOT EXISTS content_warnings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_type TEXT NOT NULL,
  content_id UUID NOT NULL,
  warning_type TEXT NOT NULL, -- 'spoiler', 'nsfw', 'violence', 'language'
  added_by TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(content_type, content_id, warning_type)
);

-- Create auto moderation rules table
CREATE TABLE IF NOT EXISTS auto_moderation_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_name TEXT NOT NULL,
  rule_type TEXT NOT NULL, -- 'keyword', 'regex', 'length', 'spam'
  pattern TEXT NOT NULL,
  action TEXT NOT NULL, -- 'flag', 'auto_remove', 'require_review'
  severity INTEGER DEFAULT 1,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE moderation_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE moderation_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_warnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE auto_moderation_rules ENABLE ROW LEVEL SECURITY;

-- RLS policies for moderation queue (admin only)
CREATE POLICY "Admins can manage moderation queue" ON moderation_queue
FOR ALL USING (
  current_setting('app.current_user_id', true) IN (
    SELECT user_id FROM user_profiles WHERE is_admin = true
  )
);

-- RLS policies for moderation actions (admin only)
CREATE POLICY "Admins can view moderation actions" ON moderation_actions
FOR SELECT USING (
  current_setting('app.current_user_id', true) IN (
    SELECT user_id FROM user_profiles WHERE is_admin = true
  )
);

CREATE POLICY "Admins can create moderation actions" ON moderation_actions
FOR INSERT WITH CHECK (
  current_setting('app.current_user_id', true) IN (
    SELECT user_id FROM user_profiles WHERE is_admin = true
  )
);

-- RLS policies for content warnings
CREATE POLICY "Anyone can view content warnings" ON content_warnings
FOR SELECT USING (true);

CREATE POLICY "Users can add content warnings" ON content_warnings
FOR INSERT WITH CHECK (added_by = current_setting('app.current_user_id', true));

-- RLS policies for auto moderation rules (admin only)
CREATE POLICY "Admins can manage auto moderation rules" ON auto_moderation_rules
FOR ALL USING (
  current_setting('app.current_user_id', true) IN (
    SELECT user_id FROM user_profiles WHERE is_admin = true
  )
);

-- Function for auto moderation check
CREATE OR REPLACE FUNCTION check_auto_moderation()
RETURNS TRIGGER AS $$
DECLARE
  rule RECORD;
  should_flag BOOLEAN := false;
  flag_reason TEXT := '';
BEGIN
  -- Check against active auto moderation rules
  FOR rule IN 
    SELECT * FROM auto_moderation_rules 
    WHERE is_active = true 
    ORDER BY severity DESC
  LOOP
    CASE rule.rule_type
      WHEN 'keyword' THEN
        IF lower(NEW.content) ~ lower(rule.pattern) THEN
          should_flag := true;
          flag_reason := 'Keyword match: ' || rule.rule_name;
          EXIT;
        END IF;
      WHEN 'length' THEN
        IF length(NEW.content) > rule.pattern::integer THEN
          should_flag := true;
          flag_reason := 'Content too long: ' || rule.rule_name;
          EXIT;
        END IF;
      -- Add more rule types as needed
    END CASE;
  END LOOP;
  
  -- If flagged, add to moderation queue
  IF should_flag THEN
    INSERT INTO moderation_queue (
      content_type,
      content_id,
      reason,
      priority
    ) VALUES (
      TG_TABLE_NAME,
      NEW.id,
      flag_reason,
      2 -- medium priority for auto-flagged content
    );
    
    -- Set status to pending if auto-remove action
    IF EXISTS (
      SELECT 1 FROM auto_moderation_rules 
      WHERE rule_name = split_part(flag_reason, ': ', 2) 
      AND action = 'auto_remove'
    ) THEN
      NEW.status := 'pending';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for auto moderation
CREATE TRIGGER auto_moderation_posts_trigger
  BEFORE INSERT ON posts
  FOR EACH ROW
  EXECUTE FUNCTION check_auto_moderation();

CREATE TRIGGER auto_moderation_comments_trigger
  BEFORE INSERT ON comments
  FOR EACH ROW
  EXECUTE FUNCTION check_auto_moderation();

-- Insert some basic auto moderation rules
INSERT INTO auto_moderation_rules (rule_name, rule_type, pattern, action, severity) VALUES
('Spam detection', 'keyword', '(buy now|click here|free money|urgent)', 'flag', 3),
('Excessive length', 'length', '5000', 'require_review', 1),
('Hate speech basic', 'keyword', '(hate|racist|bigot)', 'flag', 4);

-- Add indexes for performance
CREATE INDEX idx_moderation_queue_status ON moderation_queue(status);
CREATE INDEX idx_moderation_queue_priority ON moderation_queue(priority DESC);
CREATE INDEX idx_moderation_queue_created ON moderation_queue(created_at DESC);
CREATE INDEX idx_moderation_actions_moderator ON moderation_actions(moderator_id);
CREATE INDEX idx_moderation_actions_created ON moderation_actions(created_at DESC);
CREATE INDEX idx_content_warnings_content ON content_warnings(content_type, content_id);
CREATE INDEX idx_auto_moderation_rules_active ON auto_moderation_rules(is_active);