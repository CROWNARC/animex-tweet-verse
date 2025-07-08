import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card } from '@/components/ui/card';
import { Image, X, Plus } from 'lucide-react';
import { toast } from '@/hooks/use-toast';

interface PollOption {
  id: string;
  title: string;
  imageFile: File | null;
  imagePreview: string | null;
}

interface PollCreatorProps {
  onPollChange: (poll: { title: string; options: PollOption[] } | null) => void;
}

export const PollCreator = ({ onPollChange }: PollCreatorProps) => {
  const [pollTitle, setPollTitle] = useState('');
  const [options, setOptions] = useState<PollOption[]>([
    { id: '1', title: '', imageFile: null, imagePreview: null },
    { id: '2', title: '', imageFile: null, imagePreview: null }
  ]);
  const [showPoll, setShowPoll] = useState(false);

  const addOption = () => {
    if (options.length < 4) {
      const newOption: PollOption = {
        id: Date.now().toString(),
        title: '',
        imageFile: null,
        imagePreview: null
      };
      setOptions([...options, newOption]);
      updatePoll(pollTitle, [...options, newOption]);
    }
  };

  const removeOption = (id: string) => {
    if (options.length > 2) {
      const newOptions = options.filter(opt => opt.id !== id);
      setOptions(newOptions);
      updatePoll(pollTitle, newOptions);
    }
  };

  const updateOption = (id: string, field: keyof PollOption, value: any) => {
    const newOptions = options.map(opt => 
      opt.id === id ? { ...opt, [field]: value } : opt
    );
    setOptions(newOptions);
    updatePoll(pollTitle, newOptions);
  };

  const handleImageUpload = (id: string, file: File) => {
    if (file.size > 5 * 1024 * 1024) {
      toast({ title: "Error", description: "Image size must be less than 5MB", variant: "destructive" });
      return;
    }

    if (!file.type.startsWith('image/')) {
      toast({ title: "Error", description: "Only image files are allowed", variant: "destructive" });
      return;
    }

    const reader = new FileReader();
    reader.onload = (e) => {
      const newOptions = options.map(opt => 
        opt.id === id ? { 
          ...opt, 
          imageFile: file,
          imagePreview: e.target?.result as string 
        } : opt
      );
      setOptions(newOptions);
      updatePoll(pollTitle, newOptions);
    };
    reader.readAsDataURL(file);
  };

  const updatePoll = (title: string, opts: PollOption[]) => {
    if (!title.trim() && opts.every(opt => !opt.title.trim())) {
      onPollChange(null);
    } else {
      onPollChange({ title, options: opts });
    }
  };

  const handleTitleChange = (value: string) => {
    setPollTitle(value);
    updatePoll(value, options);
  };

  const togglePoll = () => {
    setShowPoll(!showPoll);
    if (!showPoll) {
      onPollChange(null);
      setPollTitle('');
      setOptions([
        { id: '1', title: '', imageFile: null, imagePreview: null },
        { id: '2', title: '', imageFile: null, imagePreview: null }
      ]);
    }
  };

  if (!showPoll) {
    return (
      <Button
        variant="ghost"
        size="sm"
        onClick={togglePoll}
        className="text-blue-400 hover:bg-blue-400/10"
      >
        <Plus className="h-5 w-5" />
        Poll
      </Button>
    );
  }

  return (
    <Card className="p-4 mt-3 border-blue-500/20 bg-blue-500/5">
      <div className="flex items-center justify-between mb-3">
        <h4 className="font-semibold text-blue-300">Create Poll</h4>
        <Button variant="ghost" size="sm" onClick={togglePoll}>
          <X className="h-4 w-4" />
        </Button>
      </div>

      <div className="space-y-3">
        <Input
          placeholder="Poll question..."
          value={pollTitle}
          onChange={(e) => handleTitleChange(e.target.value)}
          className="bg-background/50"
        />

        {options.map((option, index) => (
          <div key={option.id} className="flex items-center space-x-2">
            <div className="flex-1">
              <Input
                placeholder={`Option ${index + 1}`}
                value={option.title}
                onChange={(e) => updateOption(option.id, 'title', e.target.value)}
                className="bg-background/50"
              />
              {option.imagePreview && (
                <div className="mt-2 relative">
                  <img 
                    src={option.imagePreview} 
                    alt="Option preview" 
                    className="w-16 h-16 object-cover rounded"
                  />
                  <Button
                    variant="secondary"
                    size="sm"
                    className="absolute -top-2 -right-2 h-6 w-6 p-0"
                    onClick={() => updateOption(option.id, 'imageFile', null)}
                  >
                    <X className="h-3 w-3" />
                  </Button>
                </div>
              )}
            </div>
            
            <input
              type="file"
              accept="image/*"
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (file) handleImageUpload(option.id, file);
              }}
              className="hidden"
              id={`poll-image-${option.id}`}
            />
            
            <Button
              variant="ghost"
              size="sm"
              onClick={() => document.getElementById(`poll-image-${option.id}`)?.click()}
              className="text-blue-400 hover:bg-blue-400/10"
            >
              <Image className="h-4 w-4" />
            </Button>

            {options.length > 2 && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => removeOption(option.id)}
                className="text-red-400 hover:bg-red-400/10"
              >
                <X className="h-4 w-4" />
              </Button>
            )}
          </div>
        ))}

        {options.length < 4 && (
          <Button
            variant="outline"
            size="sm"
            onClick={addOption}
            className="w-full border-blue-500/20 text-blue-300 hover:bg-blue-500/10"
          >
            <Plus className="h-4 w-4 mr-2" />
            Add Option
          </Button>
        )}
      </div>
    </Card>
  );
};