# YouTrack Url and permanent token from Profile -> Account Security -> Tokens
our $YTUrl='';
our $YTtoken='';
# Url and credentials to access Jira
# Jira has changed their API to to use token auth instead of
# username and passwords. Supply a generated token for $JiraToken
our $JiraUrl='';
our $JiraLogin='';
our $JiraToken='';
# The project ID to migrate from (eg FOO, BAR)
our $YTProject='';
# YouTrack query string to narrow down which issues are migrated. Leave blank 
# to migrate the entire project.
our $YTQueryUrl='';
# The project ID to migrate to (eg FOO, BAR)
our $JiraProject='';
# Export tags from YT and import them as labels in Jira
our $exportTags='true';
# This is quite obvious
our $exportAttachments='true';
our $exportLinks='true';
our $exportWorkLog='true';
# Creation date and time will be exported in Original Creation Time field
our $exportCreationTime='true';
# You can change the name of the creation date field if you want to :)
our $creationTimeCustomFieldName='Original Date Created';
# Jira can be configured to use diffrerent time formats. Recommended is ISO8601.
# Currently there's a bug https://jira.atlassian.com/browse/JRACLOUD-61378
# Jira is not able to parse exact ISO8601 format (see the link for details)
# If you having issues with date time parsing use JIRA8601 date time format
# Possible values here: ISO8601, RFC3389, RFC822, GOST7064, JIRA8601
our $creationDateTimeFormat='JIRA8601';
# YouTrack is using regular markdown language to create rich text formatting 
# (__bold text__, _italic_, headers etc). Jira is different - it supports some 
# specific rich text formatting language. 
# If you set this to true, then you'll need to install J2M utility. See README.md file for more info.
our $convertTextFormatting='true';

# In YouTrack the Issue Type, Priority and State are stored as custom fields 
# with enum type of values by default. If you did change any of those field names, 
# please type it here
our $typeCustomFieldName="Type";
our $priorityCustomFieldName="Priority";
our $stateCustomFieldName="State";

# Lumper will keep the issue keys identical in YT and Jira if YT has no gaps larger than this value
our $maximumKeyGap=100;

# Issue type mapping
our %Type = (
	'Bug' => 'Bug',
	'Task' => 'Task',
	'Exception' => 'Bug',
	'Feature' => 'New Feature',
	'Usability Problem' => 'Bug',
	'Performance Problem' => 'Bug',
	'Build Environment' => 'Build Environment',
	'Cosmetics' => 'Bug',
	'Developer Bug' => 'Bug',
	'Developer Nice To Have' => 'Bug',
	'Documentation' => 'Task',
	'Feature Request' => 'Task',
	'Nice to have' => 'Task',
	'Performance Problem' => 'Bug',
	'Refactoring' => 'Task',
	'Test Suite' => 'Task'
);

# Issue priority mapping
our %Priority = (
	'Minor' => 'Low',
	'Normal' => 'Medium',
	'Major' => 'High',
	'Critical' => 'Critical',
	'Show-stopper' => 'Critical'
);

# Issue status mapping
# By default the Status will remain Opened
# From Jira side there should be Transitions (not Statuses) and all Transitions should be available from the initial state
our %Status = (
	#"Can't Reproduce" => "Rejected",
	#"Incomplete" => "Rejected",
	#"Obsolete" => "Rejected",
	#"On Hold" => "On Hold",
	#"To Plan" => "To Plan",
	#"Done" => "Done",
	"In Progress" => "In Progress",
	"Duplicate" => "Done",
	"Fixed" => "Done",
	"Won't fix" => "Done",
	"Verified" => "In Progress",
	"Designing" => "In Progress",
	"Estimated" => "In Progress",
	"New" => "Backlog",
	"Open" => "Selected for Development",
	"Ready" => "Peer Review",
	"Released" => "Done",
	"Reviewed" => "Peer Review",
	"System Test" => "Peer Review",
	"System Test Failed" => "In Progress",
	"System Tested" => "Peer Review"
);

# Some statuses in YT can be mapped to Resolutions in Jira
# In order to use this feature a field Resolution should be added to screens (and removed after the migration if not needed)
our %StatusToResolution = (
	#"Can't Reproduce" => "Cannot Reproduce",
	#"Obsolete" => "Obsolete",
	#"Incomplete" => "Won't Do",
	"Duplicate" => "Duplicate",
	"Won't fix" => "Declined",
	"Released" => "Done"
);

# Custom fields mapping
# Original estimate isn't found in metadata so made custom field "YouTrack Estimated Effort" 
# as a workaround.
our %CustomFields = (
	#"Found in Version" => "Affects Version/s",
	#"Found in build" => "Found in build",
	#"Target version" => "Fix Version/s",
	#"Created By" => "Original Reporter"
	#"Source" => "Source",
	"Fixed in build" => "Fixed in Build",
	"Estimated Effort" => "YouTrack Estimated Effort"
);

# Issue link types mapping
our %IssueLinks = (
	"Relates" => "Relates",
	"Duplicate" => "Duplicate",
	"Depend" => "Blocks",
	"Subtask" => "Relates"
);

# User mapping. By default the username stays the same
# Hashmap of all users that have a Jira account
our %User = (
	
);

# User mapping of all Reporter and commenter names. This
# used to convert account username abbreviations into 
# readable reporter/commentor names.
our %OriginalUser = (

);

# This hash is optional and needed to restore the comments from appropriate users. If the user is absent then his
# comments will be restored from $JiraUser and the original user will be mentioned in the comment body
our %JiraTokens = (
	
);

# When creating an issue the reporter account ID must be supplied.
our %JiraId = (
	
);