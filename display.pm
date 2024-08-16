package display;

use strict;
use warnings;
use Data::Dumper;
use POSIX "fmod";

sub new {
    my ($class, %args) = @_;
    return bless { %args }, $class;
}

our sub printTitle {
    my $self = shift;
    my $text = shift;

    print generateTitle($text);
}

sub generateTitle {
    my $text = shift;
    my $textLength = length $text;

    return "\n".generateDelimiterPart($textLength).
        " $text ".
        generateDelimiterPart($textLength + $textLength % 2)."\n";
}

# Returns one half of a delimiter for the title
sub generateDelimiterPart {
    my $textLength = shift;
    my $halfTitleLength = 76 / 2;
    my $delimiter = "--------------------".
                    "--------------------".
                    "--------------------";
                    
    # Reduce '-' symbols based on title length + 2 spaces
    # on the trim only for one side of title.
    return substr   $delimiter, 0, 
                    $halfTitleLength - 
                        int(($textLength + 2) / 2);
}

our sub printColumnAligned {
    my $self = shift;
    my $text = shift;
    
    if (length($text) < 8) {
        print $text."\t\t\t";
    } elsif (length($text) < 16) {
        print $text."\t\t";
    } elsif (length($text) < 24) {
        print $text."\t";
    } else {
        print substr ($text, 0, 21)."...\t";
    }
}

# Prints text and elapsed time
our sub printElapsedTime {
    my $self = shift;
    my $text = shift;
    my $time = shift;

    print $text.formatTVTime($time);
}

# Convert seconds to time format: x hours x minutes x seconds
# fmod is used for floating point decimal precision
sub formatTVTime {
    my $hour = 0; my $minute = 0; my $second = 0;
    $second = shift;

    if ($second > 59) {
        $minute = int($second / 60);
        $second = fmod($second, 60);
        if($minute > 59) {
            $hour = int($minute / 60);
            $minute = fmod($minute, 60);
        }
    }
    return $hour." hours ".$minute." minutes ".$second." seconds\n";
}

1;