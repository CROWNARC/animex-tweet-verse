import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { Badge } from '@/components/ui/badge';
import { Check, Vote } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { toast } from '@/hooks/use-toast';

interface PollOption {
  id: string;
  title: string;
  image_url?: string;
  vote_count: number;
  option_order: number;
}

interface Poll {
  id: string;
  title: string;
  total_votes: number;
  ends_at?: string;
  options: PollOption[];
}

interface PollDisplayProps {
  postId: string;
}

export const PollDisplay = ({ postId }: PollDisplayProps) => {
  const { user } = useAuth();
  const [poll, setPoll] = useState<Poll | null>(null);
  const [userVote, setUserVote] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchPoll();
  }, [postId]);

  const fetchPoll = async () => {
    try {
      // Fetch poll data
      const { data: pollData, error: pollError } = await supabase
        .from('polls')
        .select(`
          *,
          poll_options (*)
        `)
        .eq('post_id', postId)
        .single();

      if (pollError) {
        if (pollError.code !== 'PGRST116') { // Not found error
          console.error('Error fetching poll:', pollError);
        }
        setLoading(false);
        return;
      }

      if (pollData) {
        const sortedOptions = pollData.poll_options.sort((a: any, b: any) => a.option_order - b.option_order);
        setPoll({
          ...pollData,
          options: sortedOptions
        });

        // Check if user has voted
        if (user) {
          const { data: voteData } = await supabase
            .from('poll_votes')
            .select('option_id')
            .eq('poll_id', pollData.id)
            .eq('user_id', user.id)
            .single();

          if (voteData) {
            setUserVote(voteData.option_id);
          }
        }
      }
    } catch (error) {
      console.error('Error fetching poll:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleVote = async (optionId: string) => {
    if (!user || !poll) return;

    try {
      if (userVote) {
        // Update existing vote
        const { error } = await supabase
          .from('poll_votes')
          .update({ option_id: optionId })
          .eq('poll_id', poll.id)
          .eq('user_id', user.id);

        if (error) throw error;
      } else {
        // Create new vote
        const { error } = await supabase
          .from('poll_votes')
          .insert({
            poll_id: poll.id,
            option_id: optionId,
            user_id: user.id
          });

        if (error) throw error;
      }

      setUserVote(optionId);
      fetchPoll(); // Refresh poll data
      toast({ title: "Success", description: "Your vote has been recorded!" });
    } catch (error) {
      console.error('Error voting:', error);
      toast({ title: "Error", description: "Failed to record your vote", variant: "destructive" });
    }
  };

  if (loading) {
    return <div className="animate-pulse h-24 bg-muted rounded-lg"></div>;
  }

  if (!poll) {
    return null;
  }

  const isExpired = poll.ends_at && new Date(poll.ends_at) < new Date();
  const canVote = user && !isExpired;

  return (
    <Card className="p-4 mt-3 border-blue-500/20 bg-blue-500/5">
      <div className="flex items-center justify-between mb-3">
        <h4 className="font-semibold text-blue-300 flex items-center">
          <Vote className="h-4 w-4 mr-2" />
          {poll.title}
        </h4>
        <Badge variant="secondary" className="bg-blue-500/20 text-blue-300">
          {poll.total_votes} votes
        </Badge>
      </div>

      <div className="space-y-3">
        {poll.options.map((option) => {
          const percentage = poll.total_votes > 0 ? (option.vote_count / poll.total_votes) * 100 : 0;
          const isSelected = userVote === option.id;

          return (
            <div key={option.id} className="space-y-2">
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-2 flex-1">
                  {option.image_url && (
                    <img
                      src={option.image_url}
                      alt={option.title}
                      className="w-8 h-8 object-cover rounded"
                    />
                  )}
                  <span className="text-sm font-medium">{option.title}</span>
                  {isSelected && <Check className="h-4 w-4 text-green-400" />}
                </div>
                <span className="text-sm text-muted-foreground">
                  {option.vote_count} ({percentage.toFixed(1)}%)
                </span>
              </div>

              <div className="space-y-1">
                <Progress value={percentage} className="h-2" />
                {canVote && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleVote(option.id)}
                    disabled={isSelected}
                    className="w-full text-xs hover:bg-blue-500/10"
                  >
                    {isSelected ? 'Selected' : 'Vote'}
                  </Button>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {isExpired && (
        <p className="text-sm text-muted-foreground mt-3">This poll has ended.</p>
      )}
    </Card>
  );
};