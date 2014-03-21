package Perinci::Access::Schemeless::DBI;

use 5.010001;
use strict;
use warnings;
use experimental 'smartmatch';

use JSON;
my $json = JSON->new->allow_nonref;

use parent qw(Perinci::Access::Schemeless);

# VERSION

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    # check required attributes
    die "Please specify required attribute 'dbh'" unless $self->{dbh};

    $self;
}

sub get_meta {
    my ($self, $req) = @_;

    my $leaf = $req->{-uri_leaf};

    if (length $leaf) {
        my ($meta) = $self->{dbh}->selectrow_array(
            "SELECT metadata FROM function WHERE module=? AND name=?", {},
            $req->{-perl_package}, $leaf);
        if ($meta) {
            $req->{-meta} = $json->decode($meta);
        } else {
            return [400, "No metadata found in database"];
        }
    } else {
        # XXP check in database, if exists return if not return {v=>1.1}
        my ($meta) = $self->{dbh}->selectrow_array(
            "SELECT metadata FROM module WHERE name=?", {},
            $req->{-perl_package});
        if ($meta) {
            $req->{-meta} = $json->decode($meta);
        } else {
            $req->{-meta} = {v=>1.1}; # empty metadata for /
        }
    }
    return;
}

sub action_list {
    my ($self, $req) = @_;
    my $detail = $req->{detail};
    my $f_type = $req->{type} || "";

    my @res;

    # XXX duplicated code with parent class
    my $filter_path = sub {
        my $path = shift;
        if (defined($self->{allow_paths}) &&
                !__match_paths2($path, $self->{allow_paths})) {
            return 0;
        }
        if (defined($self->{deny_paths}) &&
                __match_paths2($path, $self->{deny_paths})) {
            return 0;
        }
        1;
    };

    my $sth;

    # get submodules
    unless ($f_type && $f_type ne 'package') {
        if (length $req->{-perl_package}) {
            $sth = $self->{dbh}->prepare(
                "SELECT name FROM module WHERE name LIKE ? ORDER BY name");
            $sth->execute("$req->{-perl_package}\::%");
        } else {
            $sth = $self->{dbh}->prepare(
                "SELECT name FROM module ORDER BY name");
            $sth->execute;
        }
        # XXX produce intermediate prefixes (e.g. user requests 'foo::bar' and
        # db lists 'foo::bar::baz::quux', then we must also produce
        # 'foo::bar::baz'
        while (my $r = $sth->fetchrow_hashref) {
            my $m = $r->{name}; $m =~ s!::!/!g;
            if ($detail) {
                push @res, {uri=>"/$m/", type=>"package"};
            } else {
                push @res, "/$m/";
            }
        }
    }

    # get all entities from this module. XXX currently only functions
    my $dir = $req->{-uri_dir};
    $sth = $self->{dbh}->prepare(
        "SELECT name FROM function WHERE module=? ORDER BY name");
    $sth->execute($req->{-perl_package});
    while (my $r = $sth->fetchrow_hashref) {
        my $e = $r->{name};
        my $path = "$dir/$e";
        next unless $filter_path->($path);
        my $t = $e =~ /^[%\@\$]/ ? 'variable' : 'function';
        next if $f_type && $f_type ne $t;
        if ($detail) {
            push @res, {
                #v=>1.1,
                uri=>$e, type=>$t,
            };
        } else {
            push @res, $e;
        }
    }

    [200, "OK (list action)", \@res];
}

1;
# ABSTRACT: Subclass of Perinci::Access::Schemeless which gets lists of entities (and metadata) from DBI database

=for Pod::Coverage ^(.+)$

=head1 SYNOPSIS

 use DBI;
 use Perinci::Access::Schemeless::DBI;

 my $dbh = DBI->connect(...);
 my $pa = Perinci::Access::Schemeless::DBI->new(dbh => $dbh);

 my $res;

 # will retrieve list of code entities from database
 $res = $pa->request(list => "/Foo/");

 # will also get metadata from database
 $res = $pa->request(meta => "/Foo/Bar/func1");

 # the rest are the same like Perinci::Access::Schemeless
 $res = $pa->request(actions => "/Foo/");


=head1 DESCRIPTION

This subclass of Perinci::Access::Schemeless gets lists of code entities
(currently only packages and functions) from a DBI database (instead of from
listing Perl packages on the filesystem). It can also retrieve L<Rinci> metadata
from said database (instead of from C<%SPEC> package variables).

Currently, you must have a table containing list of packages named C<module>
with columns C<name> (module name), C<metadata> (Rinci metadata, encoded in
JSON); and a table containing list of functions named C<function> with columns
C<module> (module name), C<name> (function name), and C<metadata> (normalized
Rinci metadata, encoded in JSON). Table and column names will be configurable in
the future. An example of the table's contents:

 name      metadata
 ----      ---------
 Foo::Bar  (null)
 Foo::Baz  {"v":"1.1"}

 module    name         metadata
 ------    ----         --------
 Foo::Bar  func1        {"v":"1.1","summary":"function 1","args":{}}
 Foo::Bar  func2        {"v":"1.1","summary":"function 2","args":{}}
 Foo::Baz  func3        {"v":"1.1","summary":"function 3","args":{"a":{"schema":["int",{},{}]}}}


=head1 HOW IT WORKS

The subclass overrides C<get_meta()> and C<action_list()>. Thus, this modifies
behaviors of the following Riap actions: C<list>, C<meta>, C<child_metas>.


=head1 METHODS

=head1 new(%args) => OBJ

Aside from its parent class, this class recognizes these attributes:

=over

=item * dbh => OBJ (required)

DBI database handle.

=back


=head1 FAQ

=head2 Rationale for this module?

If you have a large number of packages and functions, you might want to avoid
reading Perl modules on the filesystem.


=head1 TODO

=over

=item * Support other types of entities: variables, ...

Currently only packages and functions are recognized.

=item * Get code from database?

=item * Make into a role?

So users can mix and match either one or more of these as they see fit: getting
list of modules and functions from database, getting metadata from database, and
getting code from database.

Alternatively, this single class can provide all of those and switch to enable
each.

=back


=head1 SEE ALSO

L<Riap>, L<Rinci>

=cut
