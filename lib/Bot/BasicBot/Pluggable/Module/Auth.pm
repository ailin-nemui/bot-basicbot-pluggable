package Bot::BasicBot::Pluggable::Module::Auth;
use base qw(Bot::BasicBot::Pluggable::Module);
use warnings;
use strict;
use Crypt::SaltedHash;

sub init {
    my $self = shift;
    $self->config(
        {
            password_admin  => "julia",
            allow_anonymous => 0,
        }
    );
}

sub help {
    return
"Authenticator for admin-level commands. Usage: !auth <username> <password>, !adduser <username> <password>, !deluser <username>, !password <old password> <new password>, !users.";
}

sub admin {
    my ( $self, $mess ) = @_;
    my $body = $mess->{body};

    return unless ( $body and length($body) > 4 );

    # we don't care about commands that don't start with '!'.
    return 0 unless $body =~ /^!/;

    # system commands have to be directly addressed...
    return 1 unless $mess->{address};

    # ...and in a privmsg.
    return "Admin commands in privmsg only, please."
      unless !defined $mess->{channel} || $mess->{channel} eq 'msg';

    if ( $body =~ /^!auth\s+(\w+)\s+(\w+)/ ) {
        my ( $user, $pass ) = ( $1, $2 );
        my $stored = $self->get( "password_" . $user );

        if ( _check_password($pass, $stored) ) {
            $self->{auth}{ $mess->{who} }{time}     = time();
            $self->{auth}{ $mess->{who} }{username} = $user;
            if ( $user eq "admin" and $pass eq "julia" ) {
                return
"Authenticated. But change the password - you're using the default.";
            }
            return "Authenticated.";
        }
        else {
            delete $self->{auth}{ $mess->{who} };
            return "Wrong password.";
        }
    }
    elsif ( $body =~ /^!auth/ ) {
        return "Usage: !auth <username> <password>.";

    }
    elsif ( $body =~ /^!adduser\s+(\w+)\s+(\w+)/ ) {
        my ( $user, $pass ) = ( $1, $2 );
        if ( $self->authed( $mess->{who} ) ) {
            $self->set( "password_" . $user, _hash_password($pass) );
            return "Added user $user.";
        }
        else {
            return "You need to authenticate.";
        }
    }
    elsif ( $body =~ /^!adduser/ ) {
        return "Usage: !adduser <username> <password>";

    }
    elsif ( $body =~ /^!deluser\s+(\w+)/ ) {
        my $user = $1;
        if ( $self->authed( $mess->{who} ) ) {
            $self->unset( "password_" . $user );
            return "Deleted user $user.";
        }
        else {
            return "You need to authenticate.";
        }
    }
    elsif ( $body =~ /^!deluser/ ) {
        return "Usage: !deluser <username>";

    }
    elsif ( $body =~ /^!passw?o?r?d?\s+(\w+)\s+(\w+)/ ) {
        my ( $old_pass, $pass ) = ( $1, $2 );
        if ( $self->authed( $mess->{who} ) ) {
            my $username = $self->{auth}{ $mess->{who} }{username};
            if (_check_password($old_pass, $self->get("password_$username")) ) {
                $self->set( "password_$username", _hash_password($pass) );
                return "Changed password to $pass.";
            }
            else {
                return "Wrong password.";
            }
        }
        else {
            return "You need to authenticate.";
        }
    }
    elsif ( $body =~ /^!passw?o?r?d?/ ) {
        return "Usage: !password <old password> <new password>.";

    }
    elsif ( $body =~ /^!users/ ) {
        return "Users: "
          . join( ", ",
            map { my $user = $_; $user =~ s/^password_// ? $user : () }
              $self->store_keys( res => ["^password"] ) )
          . ".";
    }
    else {
        return
          if $self->get("allow_anonymous") || $self->authed( $mess->{who} );
        return "You need to authenticate.";
    }
}

sub authed {
    my ( $self, $username ) = @_;
    return 1
      if (  $self->{auth}{$username}{time}
        and $self->{auth}{$username}{time} + 7200 > time() );
    return 0;
}

# Given a password provided by the user and the password stored in the database,
# see if they match.  Older versions stored plaintext passwords, newer versions
# use salted hashed passwords.
sub _check_password {
    my ($entered_pw, $stored_pw) = @_;
    if ($stored_pw =~ /^\{SSHA\}/) {
        return Crypt::SaltedHash->validate($stored_pw, $entered_pw);
    } else {
        return $entered_pw eq $stored_pw;
    }
}

# Given a plain-text password, return a salted hashed version to store
sub _hash_password {
    my $plain_pw = shift;
    my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
    $csh->add($plain_pw);
    return $csh->generate;
}

1;
__END__

=head1 NAME

Bot::BasicBot::Pluggable::Module::Auth - authentication for Bot::BasicBot::Pluggable modules

=head1 SYNOPSIS

This module catches messages at priority 1 and stops anything starting
with '!' unless the user is authed. Most admin modules, e.g. Loader, can
merely sit at priority 2 and assume the user is authed if the !command
reaches them. If you want to use modules that can change bot state, like
Loader or Vars, you almost certainly want this module.

=head1 IRC USAGE

The default user is 'admin' with password 'julia'. Change this.

=over 4

=item !auth <username> <password>

Authenticate as an administrators. Logins timeout after an hour.

=item !adduser <username> <password>

Adds a user with the given password.

=item !deluser <username>

Deletes a user. Don't delete yourself, that's probably not a good idea.

=item !password <old password> <new password>

Change your current password (must be logged in first).

=item !users

List all the users the bot knows about.

=back

=head1 VARIABLES

=over 4

=item password_admin

This variable specifies the admin password. Its normally set via the
!password directive and defaults to 'julia'. Please change this as soon
as possible.

=item allow_anonymous

If this variable is true, the implicit authentication handling is
disabled. Every module will have to check for authentication via the
authed method, otherwise access is just granted. This is only usefull
to allow modules to handle directives starting with an exclamation
mark without needing any authentication. And to make things even more
interesting, you won't be warned that you have't authenticated, so modules
needing authentication will fail without any warning. It defaults to
false and should probably never be changed. You've been warned.

=back

=head1 METHODS

The only useful method is C<authed()>:

=over 4

=item authed($username)

Returns 1 if the given username is logged in, 0 otherwise:

  if ($bot->module("Auth")->authed("jerakeen")) { ... }

=back

=head1 BUGS

All users are admins. This is fine at the moment, as the only things that need
you to be logged in are admin functions. Passwords are stored in plaintext, and
are trivial to extract for any module on the system. I don't consider this a
bug, because I assume you trust the modules you're loading. If Auth is I<not>
loaded, all users effectively have admin permissions. This may not be a good
idea, but is also not an Auth bug, it's an architecture bug.

=head1 AUTHOR

Mario Domgoergen <mdom@cpan.org>

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.
