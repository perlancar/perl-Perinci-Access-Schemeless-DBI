#!perl

use 5.010;
use strict;
use warnings;

use DBI;
use File::chdir;
use File::Temp qw(tempdir);
use JSON;
use Perinci::Access::Schemeless;
use Perinci::Access::Schemeless::DBI;
use Test::More 0.98;

# the idea of the tests is: setup a random/unique package, store the meta in the
# db, and check that we can list/meta into it, even though the package does not
# exist yet in perl.

my $json = JSON->new->allow_nonref;
my $rootdir = tempdir(CLEANUP=>1);
$CWD = $rootdir;
my $dbh = DBI->connect("dbi:SQLite:dbname=$rootdir/db.db", '', '',
                       {RaiseError=>1});
my $uniq = join('', map {("a".."z")[26*rand()]} 1..10);
my $pkg = "Test::$uniq";

# setup db
$dbh->do("CREATE TABLE module (name TEXT PRIMARY KEY, metadata TEXT)");
for (
    {name=>"$pkg", metadata=>undef},
    {name=>"$pkg\::sub", metadata=>{v=>1.1, summary=>"blah"}},
) {
    $dbh->do("INSERT INTO module (name,metadata) VALUES (?,?)", {},
             $_->{name}, $json->encode($_->{metadata}));
}
$dbh->do("CREATE TABLE function (module TEXT, name TEXT, metadata TEXT)");
for (
    {module=>$pkg, name=>"f1", metadata=>{v=>1.1, summary=>"f1"}},
    {module=>$pkg, name=>"f3", metadata=>{v=>1.1, summary=>"f3"}},
    {module=>$pkg, name=>"f2", metadata=>{v=>1.1, summary=>"f2"}},
    {module=>$pkg, name=>"f4", metadata=>{v=>1.1, summary=>"f4"}},
    {module=>"$pkg\::sub", name=>"f1", metadata=>{v=>1.1, summary=>"sf1"}},
) {
    $dbh->do("INSERT INTO function (module,name,metadata) VALUES (?,?,?)", {},
             $_->{module}, $_->{name}, $json->encode($_->{metadata}));
}

# test
my $pa = Perinci::Access::Schemeless::DBI->new(dbh=>$dbh);

test_request(
    name   => "list 1",
    argv   => [list => "/Test/$uniq/"],
    result => [qw(sub/ f1 f2 f3 f4)],
);
test_request(
    name   => "list detail 1",
    argv   => [list => "/Test/$uniq/", {detail=>1}],
    result => [
        {uri=>"sub/", type=>"package" },
        {uri=>"f1"  , type=>"function"},
        {uri=>"f2"  , type=>"function"},
        {uri=>"f3"  , type=>"function"},
        {uri=>"f4"  , type=>"function"},
    ],
);
test_request(
    name   => "list sub",
    argv   => [list => "/Test/$uniq/sub/"],
    result => [qw(f1)],
);

test_request(
    name   => "meta 1",
    argv   => [meta => "/Test/$uniq/f1"],
    result => {v=>1.1, summary=>"f1"},
);
test_request(
    name   => "meta not found",
    argv   => [meta => "/Test/$uniq/f5"],
    status => 404,
);

test_request(
    name   => "child_metas 1",
    argv   => [child_metas => "/Test/$uniq/"],
    result => {
        f1 => {v=>1.1, summary=>'f1'},
        f2 => {v=>1.1, summary=>'f2'},
        f3 => {v=>1.1, summary=>'f3'},
        f4 => {v=>1.1, summary=>'f4'},
        "sub/" => {v=>1.1, summary=>'blah'},
    },
);

test_request(
    name   => "call 1",
    argv   => [call => "/Test/$uniq/f1"],
    status => 404,
);

DONE_TESTING:
done_testing;
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    # don't delete test data dir if there are errors
    diag "there are failing tests, not deleting test data dir $rootdir";
}

sub test_request {
    my %args = @_;
    my $name = $args{name} // join(" ", @{ $args{argv} });
    subtest $name => sub {
        my $res = $pa->request(@{ $args{argv} });
        my $exp_status = $args{status} // 200;
        is($res->[0], $exp_status, "status")
            or diag explain $res;
        return unless $exp_status == 200;

        if (exists $args{result}) {
            is_deeply($res->[2], $args{result}, "result")
                or diag explain $res;
        }
    };
}
