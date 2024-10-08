#!/usr/bin/perl

use File::Basename qw/dirname/;
use File::Temp qw ( tempdir );
use lib dirname(__FILE__);
use display;
use youtrack;
use check;
use jira;
require "config.pl";

use Data::Dumper;
use Getopt::Long;
use IPC::Run qw( run );
use Date::Format;
use Encode;

use Time::HiRes qw(usleep gettimeofday tv_interval);

# Used to display column-like output
my $display = display->new(); 

$display->printTitle("Initialization");

my ($skip, $notest, $maxissues, $cookieFile, $verbose);
Getopt::Long::Configure('bundling');
GetOptions(
    "skip|s=i"      => \$skip,
    "no-test|t"      => \$notest,
    "max-issues|m=i" => \$maxissues,
    "cookie-file|c=s" => \$cookieFile,
    "verbose|v"       => \$verbose
);

my $yt = youtrack->new( Url      => $YTUrl,
                        Token    => $YTtoken,
                        Verbose  => $verbose,
						Project  => $YTProject );

unless ($yt) {
	die "Could not login to $YTUrl";
}

my $jira = jira->new(	Url         => $JiraUrl,
                    	Login       => $JiraLogin,
                      	Password    => $JiraToken,
                      	Verbose     => $verbose,
                      	Project     => $JiraProject,
		      		 	CookieFile => $cookieFile,
);

unless ($jira) {
    die "Could not login to $JiraUrl\n";
}

print "Success\n";

$display->printTitle("Getting YouTrack Issues");

my $export = $yt->exportIssues(Project => $YTProject, SearchQuery => $YTQueryUrl, Max => $maxissues);
print "Exported issues: ".scalar @{$export}."\n";

# Find active users from issues, commetns and other YT activity
my %users;
foreach my $issue (@{$export}) {
	$users{$issue->{Assignee}} = 1;
	$users{$issue->{reporter}->{login}} = 1;
	foreach (@{$issue->{comments}}) {
		$users{$_->{author}->{login}} = 1;
	}
}
# Join those active with those that are listed in config 
# in case if config ones are not listed in the %users
foreach my $configUser (keys %User) {
	$users{$configUser} = 1;
}
print Dumper(%users) if ($verbose);

my $check = check->new( 
	Jira => $jira,
	YouTrack => $yt,
	Url => $JiraUrl,
	JiraLogin => $JiraLogin,
	Passwords => \%JiraTokens,
	RealUsers =>  \%users,
	Users => \%User,
	JiraId => \%JiraId,
	TypeFieldName => $typeCustomFieldName,
	Types => \%Type,
	Links => \%IssueLinks,
	ExportCreationTime => $exportCreationTime,
	CreationTimeFieldName => $creationTimeCustomFieldName,
	Fields => \%CustomFields,
	PriorityFieldName => $priorityCustomFieldName,
	Priorities => \%Priority,
	StatusFieldName => $stateCustomFieldName,
	Statuses => \%Status,
	StatusToResolutions => \%StatusToResolution
);

%User = %{$check->users()};

unless ($notest) {
	$check->passwords();
	$check->issueTypes();
	$check->issueLinks();
	$check->fields();
	$check->priorities();
	$check->statuses();
	$check->resolutions();

	&ifProceed;
}

$display->printTitle("Starting Timer");
my $startTime = [gettimeofday];

my $issuesCount = 0;

$display->printTitle("Export To Jira");

foreach my $issue (sort { $a->{numberInProject} <=> $b->{numberInProject} } @{$export}) {
	$display->printTitle($YTProject."-".$issue->{numberInProject});
	
	if ($skip && $issue->{numberInProject} <= $skip) {
		print "Skipping issue $YTProject-".$issue->{numberInProject}."\n";
		next;
	}
	$issuesCount++;
	last if ($maxissues && $issuesCount>$maxissues);
	
	my $attachmentFileNamesMapping;
	my $attachments;

	# Download attachments
	if ($exportAttachments eq 'true') {
		print "Check for attachments\n";
		($attachments, $attachmentFileNamesMapping) = $yt->downloadAttachments(IssueKey => $issue->{id});
		print Dumper(@{$attachments}) if ($verbose);
	}

	print "Will import issue $YTProject-".$issue->{numberInProject}."\n";

	# Prepare creation time message if exportCreationTime setting is not set
	my $creationTime = scalar localtime ($issue->{created}/1000);
	my $header = "";
	if (not($exportCreationTime)) {
		$header .= "[Created ";
		if ($User{$issue->{reporter}->{login}} eq $JiraLogin) { 
			$header .= "by ".$issue->{reporter}->{login}." "; 
		}
		$header .= $creationTime;
		$header .= "]\n";
	}

	# Convert Markdown to Jira-specific rich text formatting
	my $description = convertUserMentions($issue->{description});
	$description = convertAttachmentsLinks($description, $attachmentFileNamesMapping);

	if($convertTextFormatting eq 'true') {	
		$description = convertCodeSnippets($description);
		$description = convertQuotations($description);
		$description = convertMarkdownToJira($description);
	}
	
	# In Jira Cloud, the user ID is required now instead of just a name
	# Only users with an account are allowed to be reporters
	my %import = ( project => { key => $JiraProject },
	               issuetype => { name => $Type{$issue->{$typeCustomFieldName}} || $issue->{$typeCustomFieldName} },
                   assignee => { name => $User{$issue->{Assignee}} || $issue->{Assignee} },
                   reporter => { id => $JiraId{$User{$issue->{reporter}->{login}}} }, 
                   summary => $issue->{summary},
                   description => $header.$description,
                   priority => { name => $Priority{$issue->{Priority}} || $issue->{Priority} || 'Medium' }
	);

	# Let's check through custom fields
	my %custom;
	foreach my $field (keys %CustomFields) {
		if (defined $issue->{$field}) {
			$custom{$CustomFields{$field}} = $issue->{$field};
		}
	}
	# Display the name of the reporter from the YouTrack issue in the Jira 
	# custom field Original Reporter
	$custom{"Original Reporter"} = $OriginalUser{$issue->{reporter}->{login}};	

	# Epic Name special field is required for Jira Epic issues type
	if ($import{issuetype}->{name} == 'Epic') {
		$custom{"Epic Name"} = $issue->{summary};
	}
	
	# Add YouTrack original creation date field	
	my %dateTimeFormats = (
		RFC822 => "%a, %d %b %Y %H:%M:%S %z",
		RFC3389 => "%Y-%m-%dT%H:%M:%S%z",
		ISO8601 => "%Y-%m-%dT%T%z",
		GOST7.0.64 => "%Y%m%dT%H%M%S%z",
		JIRA8601 => "%Y-%m-%dT%T.00%z"
	);
	if ($exportCreationTime eq 'true') {
		my @parsedTime = localtime ($issue->{created}/1000);
		$custom{$creationTimeCustomFieldName} = strftime($dateTimeFormats{"$creationDateTimeFormat"}, @parsedTime);
	}

	# Let's check for labels
	if ($exportTags eq 'true') {
		my @tags = $yt->getTags(IssueKey => $issue->{id});
		if (@tags) {
			$import{labels} = [@tags];
			print "Found tags: ".Dumper(@tags) if ($verbose);
		}
	}
	
	my $key = $jira->createIssue(Issue => \%import, CustomFields => \%custom) || warn "Error while creating issue";
	print "Jira issue key generated $key\n";

	# Checking issue number in key (eg in FOO-20 the issue number is 20)
	if ($key =~ /^[A-Z]+-(\d+)$/) {
		while ( $1 < $issue->{numberInProject} && ($issue->{numberInProject} - $1) <= $maximumKeyGap ) {
			print "We're having a gap and will delete the issue\n";
			unless ($jira->deleteIssue(Key => $key)) {
				warn "Error while deleting the issue $key";
			}
			$key = $jira->createIssue(Issue => \%import, CustomFields => \%custom) || warn "Error while creating issue";
			print "\nNew Jira issue key generated $key\n";
			$key =~ /^[A-Z]+-(\d+)$/;
		}
	} else {
		die "Wrong issue key $key";
	}

	# Save Jira issue key for forther linking
	$issue->{jiraKey} = $key;

	# Transition
	if ($Status{$issue->{State}}) {
		print "\nChanging status to ".$Status{$issue->{State}}."\n";
		unless ($jira->doTransition(Key => $key, Status => $Status{$issue->{State}})) {
			warn "Failed doing transition";
		}
	}

	# Resolution
	if ($StatusToResolution{$issue->{State}}) {
		print "\nChanging resolution to ".$StatusToResolution{$issue->{State}}."\n";
		unless ($jira->changeFields(Key => $key, Fields => { 'Resolution' => $StatusToResolution{$issue->{State}} } )) {
			warn "Failed updating fields"
		}
	}

	# Create comments
	print "\nCreating comments\n";
	# Comments were being shown from newest to oldest. Added reverse so
	# comment list would display from oldest to newest.
	foreach my $comment (reverse(@{$issue->{comments}})) {
		my $author = $User{$comment->{author}->{login}} || $comment->{author}->{login};
		my $date = scalar localtime ($comment->{created}/1000);

		my $text = $comment->{text};
		
		# Convert Markdown to Jira-specific rich text formatting
		$text = convertUserMentions($text);
		$text = convertAttachmentsLinks($text, $attachmentFileNamesMapping);

		if($convertTextFormatting eq 'true') {
			$text = convertCodeSnippets($text);
			$text = convertQuotations($text);
			$text = convertMarkdownToJira($text);
		}

		my $header;
		if ( $JiraTokens{$author} ) {
			$header = "[ $date ]\n";
			$text = $header.$text;
			my $jiraComment = $jira->createComment(IssueKey => $key, Body => $text, Login => $author, Password => $JiraTokens{$author}) || warn "Error creating comment";
		} else {
			my $commentAuthor = $OriginalUser{$comment->{author}->{login}} || $comment->{author}->{login}; # Displays the full name of the original author instead of an account abbreviation
			$header = "[ ".$commentAuthor." $date ]\n";
			$text = $header.$text;
			my $jiraComment = $jira->createComment(IssueKey => $key, Body => $text) || warn "Error creating comment";
		}
	}

	# Export work log
	if ($exportWorkLog eq 'true') {
		print "\nExporting work log\n";
		my $workLogs = $yt->getWorkLog( IssueKey => $issue->{idReadable} );
		foreach my $workLog (@{$workLogs->{workItems}}) {
			my @parsedTime = localtime ($issue->{created}/1000);
			my %jiraWorkLog = (
				author => { 
					name => $User{ $workLog->{author}->{login} }
				},
				comment => $workLog->{text},
				started => strftime($dateTimeFormats{"$creationDateTimeFormat"}, @parsedTime),
				timeSpentSeconds => $workLog->{duration}->{minutes} * 60
			);

			if ( defined $JiraTokens{$User{ $workLog->{author}->{login} }} ) {
				$jira->addWorkLog(Key => $key, 
								WorkLog => \%jiraWorkLog, 
								Login => $User{ $workLog->{author}->{login} }, 
								Password => $JiraTokens{$User{ $workLog->{author}->{login} }}) 
					|| warn "\nError creating work log";
			} else {
				my $originalAuthor = "[ Original Author: ".$OriginalUser{$workLog->{author}->{login}}." ]\n"; # Displays the full name of the original author instead of an account abbreviation
				$jiraWorkLog{comment} = $originalAuthor."".$jiraWorkLog{comment};
				$jira->addWorkLog(Key => $key, WorkLog => \%jiraWorkLog) 
					|| warn "\nError creating work log";
			}			
		}
	}

	# If descriptions exceeds Jira limitations - save it as an attachment
	if (length $header.$description >= 32766) {
		print "\nDescription exceeds Jira max symbol limitation and will be saved as attachment.\n";
		my $tempdir = tempdir();
		open my $fh, ">", "$tempdir/description.md";
		binmode $fh, "encoding(UTF-8)";
		print $fh $issue->{description};
		close $fh;
		push @{$attachments}, "$tempdir/description.md";
	}

	# Upload attachments to Jira
	if (@{$attachments}) {
		print "Uploading ".scalar @{$attachments}." files\n";
		unless ($jira->addAttachments(IssueKey => $key, Files => $attachments)) {
			warn "Cannot upload attachment to $key";
		}
	}
}

my $issueMigrationTime = tv_interval($startTime);
my $issueLinkStart = [gettimeofday];

# Create Issue Links
if ($exportLinks eq 'true') {	
	$display->printTitle("Creating Issue Links");
	# Turn YT issues to a hash to be able to search for issue ID
	my %issuesById = map { $_->{id} => $_ } @{$export};
	# Keep linked issues in hash to avoid duplicates on BOTH type of links
	my %alreadyEstablishedLinksWith = map { $_ => () } keys %IssueLinks;

	foreach my $issue (sort { $a->{numberInProject} <=> $b->{numberInProject} } @{$export}) {
		my $links = $yt->getIssueLinks(IssueKey => $issue->{id});

		foreach my $link (@{$links}) {
			my $jiraLink;

			# If this link does not have any issues attached - skip to the next one
			if (!@{$link->{issues}}){
				next;
			}

			# Check if config has this issue link type name
		    if (defined $IssueLinks{$link->{linkType}->{name}}) {
        		$jiraLink->{type}->{name} = $IssueLinks{$link->{linkType}->{name}};
    		} else {
        		next;
    		}

			foreach my $linkedIssue (@{$link->{issues}}) {
				if (exists $issuesById{$linkedIssue->{id}}) {
					if ($link->{direction} eq 'INWARD' || $link->{direction} eq 'BOTH') {
						$jiraLink->{inwardIssue}->{key} = $issue->{jiraKey};
						$jiraLink->{outwardIssue}->{key} = $issuesById{$linkedIssue->{id}}->{jiraKey};
					} elsif ($link->{direction} eq 'OUTWARD') {						
						$jiraLink->{inwardIssue}->{key} = $issuesById{$linkedIssue->{id}}->{jiraKey};
						$jiraLink->{outwardIssue}->{key} = $issue->{jiraKey};
					} 

					if (not $alreadyEstablishedLinksWith{$link->{linkType}->{name}}{$linkedIssue->{id}}) {
						print "Creating link between ".$jiraLink->{outwardIssue}->{key}." and ".$jiraLink->{inwardIssue}->{key}."\n";

						if ($jira->createIssueLink( Link => $jiraLink )) {
							# To avoid link duplications (for BOTH direction type of issue link)
							$alreadyEstablishedLinksWith{$link->{linkType}->{name}}{$linkedIssue->{id}} = 1;
							$alreadyEstablishedLinksWith{$link->{linkType}->{name}}{$issue->{id}} = 1;
							print " Done\n";
						} else {
							print " Failed. Most likely the second issue is not migrated yet\n";
						}
					}
				}
			}
		}		
	}
}

my $issueLinkFinish = tv_interval($issueLinkStart);
my $totalTime = tv_interval($startTime);

$display->printTitle("Stopping Timer");

$display->printTitle("Timer Statistics");
$display->printElapsedTime("\nYouTrack to Jira Migration Time: ", $issueMigrationTime);
$display->printElapsedTime("Issue Link Time: ", $issueLinkFinish);
$display->printElapsedTime("Total Elapsed Migration Time: ", $totalTime);

$display->printTitle("ENJOY :)");

sub ifProceed {
	print "\nProceed? (y/N) ";
	my $input = <>;
	chomp $input;
	exit unless (lc($input) eq 'y');
}

# Converts Markdown text format to Jira format using J2M utility
sub convertMarkdownToJira {
	my $textToConvert = shift;
	
	my @j2mCommand = ('j2m', '--toJ', '--stdin');
	run(\@j2mCommand, \$textToConvert, \my $j2mConvertedText) 
		or die "Something wrong with J2M tool, is it installed? ".
		"Try install it using:\n\n\tnpm install j2m --save\n\n";
	return decode_utf8($j2mConvertedText);
}

# Converts user mentions to correct usernames 
sub convertUserMentions {
	my $textToConvert = shift;

	# Convert user @foo mentions to Jira [~foo] links
	if ( $JiraTokens{$1} ) {
		$textToConvert =~ s/\B\@(\S+)/\[\~$User{$1}\]/g;
	} else {
		# If we do not have the user credentials display 
		# the users name instead of a failed link
		$textToConvert =~ s/\B\@(\S+)/\[$OriginalUser{$1}\]/g;
	}

	return $textToConvert;
}

# Converts links to attachments 
sub convertAttachmentsLinks {
	my $textToConvert = shift;
	my $attachmentFileNamesMapping = shift;

	# Convert attachment ![](image.png) links to Jira links !image.png|thumbnail!
	$textToConvert =~ s/!\[\]\((.+?)\)/"!".%{$attachmentFileNamesMapping}{$1}."|thumbnail!"/eg;

	return $textToConvert;
}

sub convertCodeSnippets {
	my $textToConvert = shift;

	# Convert ``` to {code}
	$textToConvert =~ s/```(\w*)\n/($1 ? "{code:$1}\n" : "{code}\n")/eg;
	$textToConvert =~ s/```/\n{code}\n/g;

	return $textToConvert;
}

sub convertQuotations {
	my $textToConvert = shift;

	# Convert > to {quote}
	$textToConvert =~ s/^> *(.*)/{quote}\n$1\n{quote}/gm;

	return $textToConvert;
}