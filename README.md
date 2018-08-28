# bugzilla2gitea
Set of tools to convert from Bugzilla to Gitea (possibly Gogs). Assumes Gitea is using MySQL, but could be easily adapted.

## Features
- Copies Bugzilla bugs into Gitea issues
- Transfers all comments
- Can keep a map of moved bugs to allow further migration e.g. attachments or link redirects
- Small!

## Attachments
- See `misc/archive_attachments.pl`. Use with the optional CSV that `bugzilla2gitea` can create.
- Retrieves attachments from Bugzilla's database, allows you to post them to a web server.
- Posts links on the corresponding Gitea bugs for the old Bugzilla attachments.

## Caveats
- Modifies Gitea's database raw in order to preserve metadata such as dates.
- Doesn't transfer attachments (yet - likely to be a separate script).
- Less risk with a (nearly) clean install rather than a live, in-use, production copy. Use this before you deploy to the public.

## Usage
- Take a backup of your Gitea database first!
- Configure your Bugzilla and Gitea (DB) credentials (and the map option if desired).
- Check your 'user' and 'repository' tables in the DB for the user to post as and target repo and adjust accordingly.
- Double check you took a backup, then run: `./bugzilla2gitea`.

## Prerequisites
- DBD::MySQL (Debian-like: libdbd-mysql-perl)
- LWP::UserAgent (Debian-like: libwww-perl)
- Date::Parse (Debian-like: libtimedate-perl)
