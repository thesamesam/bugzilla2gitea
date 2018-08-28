#!/usr/bin/perl
# NAME: archive_attachments.pl
# AUTHOR: sam <sam@cmpct.info>
# Grabs attachments from Bugzilla, copies them to a directory, and posts links to them in corresponding Gitea issues
# Intended to be used with bugzilla2gitea

# Assumes Bugzilla is using SQLite and Gitea is using MySQL
# Should be easy to change

use strict;
use warnings;

use Date::Parse;
use DBI; # libdbd-sqlite3-perl
use File::Path qw(make_path);

use Data::Dumper;

# Config
my $BUGZILLA_DB_FILE = "../bugs.sqlite";
my $BUGZILLA_PROJ    = "myproject";

my $GITEA_MYSQL_HOST = "127.0.0.1";
my $GITEA_MYSQL_USER = "gitea";
my $GITEA_MYSQL_PASS = "password";
my $GITEA_MYSQL_DB   = "gitea";

# Folder to place the scraped attachments in
my $ARCHIVE_FOLDER = "attachments";

# Where is the .csv containing [project, old Bugzilla ID, new Gitea ID]?
# (bugzilla2gitea can generate this for you)
my $ARCHIVE_MAP    = "../bugzilla2gitea_old_to_new.csv";

# Location where you'll place $ARCHIVE_FOLDER (no trailing /)
my $HTTP_PATH      = "https://example.com/old_bugzilla_attachments";

# NOTE: You need to find these from the 'user' and 'repository' tables in MySQL for the user you want to pretend to post as (and the target repo)
my $GITEA_POSTER_ID  = 1;
my $GITEA_REPO_ID    = 2;

# End config

sub find_attachments() {
    my %bugs_to_files;
    my $db_handle = connect_to_sqlite();
    my $query     = $db_handle->prepare("SELECT * FROM attachments");
    $query->execute();

    while(my $row = $query->fetchrow_arrayref()) {
        my $id           = $row->[0];
        my $bug_id       = $row->[1];
        my $creation_ts  = str2time($row->[2]);
        my $mod_ts       = str2time($row->[3]);
        my $description  = $row->[4];
        my $mime_type    = $row->[5];
        my $is_patch     = $row->[6];
        my $filename     = $row->[7];
        my $submitter_id = $row->[8];
        my $is_obsolete  = $row->[9];
        my $is_private   = $row->[10];

        # Get the corresponding Gitea bug
        my $new_bug_id = old_bug_to_new_bug($bug_id);
        if($new_bug_id < 0) {
            # If no such bug map was found, then this attachment isn't for us.
            # i.e. the bug ID is for another project.
            next;
        }

        # Get the corresponding attachment file for the attachment metadata we found
        my $data_query = $db_handle->prepare("SELECT thedata FROM attach_data WHERE id=?");
        $data_query->execute($id);
        my $data = $data_query->fetch()->[0];

        print "[bz_id $bug_id] -> [gitea_id $new_bug_id] [$filename] [$mime_type]", "\r\n";

        # Write the attachment to a file
        write_bug_to_file($bug_id, $creation_ts . "." . $filename, $data);

        # Keep track of which bugs have which attachments
        push @{$bugs_to_files{$bug_id}}, $filename;
    }

    # Write a comment on Gitea about it saying with a list of links to the attachments for that bug (all in one comment)
    my $mysql_db_handle = connect_to_mysql();

    print "Files retrieved. Writing links to Gitea issues... (this will take some time)\r\n";
    foreach my $key (keys %bugs_to_files) {
        my $bz_bug_id  = $key;
        my $new_bug_id = old_bug_to_new_bug($bz_bug_id);
        my $files      = $bugs_to_files{$key};
        my $time       = time();
        my $comment    = "For this bug (old bug $bz_bug_id), the following archived attachments exist:\r\n";

        foreach my $file (@$files) {
            $comment .= "$HTTP_PATH/$ARCHIVE_FOLDER/$bz_bug_id/$file\r\n";
        }

        # We need to know the internal issue ID, not the external one
        $query = $mysql_db_handle->prepare('SELECT id FROM issue WHERE issue.index=? AND issue.repo_id=?');
        $query->execute($new_bug_id, $GITEA_REPO_ID);
        my $new_bug_id_internal = $query->fetchrow_arrayref()->[0];

        # Create the comment in Gitea's DB
        $query = $mysql_db_handle->prepare('INSERT INTO comment VALUES (NULL,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
        $query->execute(0, $GITEA_POSTER_ID, $new_bug_id_internal, 0, 0, 0, 0, 0, "", "",
                        0, 0, $comment, $time, $time, "");
    }
}

sub write_bug_to_file() {
    # Writes attachment contents to a file
    my $old_id   = shift;
    my $filename = shift;
    my $data     = shift;
    my $path     = "$ARCHIVE_FOLDER/$old_id/";

    make_path($path);

    open(my $fh, ">", $path . $filename);
    print $fh $data;
    close($fh);
}

sub old_bug_to_new_bug() {
    # Reads the CSV ($ARCHIVE_MAP) and finds the new Gitea ID for the given Bugzilla ID
    my $target_old = shift;
    my $result     = -1;

    open(my $FH, "<", $ARCHIVE_MAP);

    while(my $line = readline($FH)) {
        # Strip the newline character
        $line =~ s/\r\n//;

        my @parts  = split(",", $line);
        my $proj   = $parts[0];
        my $old_id = $parts[1];
        my $new_id = $parts[2];

        if ($target_old eq $old_id && $BUGZILLA_PROJ eq $proj) {
            $result = $new_id;
            last;
        }

    }

    close($FH);

    return $result;
}

sub connect_to_sqlite() {
    my $DBH = DBI->connect("dbi:SQLite:dbname=$BUGZILLA_DB_FILE", "", "");
    return $DBH;
}

sub connect_to_mysql() {
    # TODO: Could support other DBs
    my $DBH = DBI->connect("DBI:mysql:database=$GITEA_MYSQL_DB;host=$GITEA_MYSQL_HOST",
                            $GITEA_MYSQL_USER, $GITEA_MYSQL_PASS,
                            {'RaiseError' => 1}) or die "Failed to connect to MySQL: $!";
    return $DBH;
}

find_attachments();