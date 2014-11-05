use strict; use warnings;
package Inline::Module;
our $VERSION = '0.02';

use File::Path;
use File::Copy;
use Inline();

#                     use XXX;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub run {
    my ($self) = @_;
    $self->get_opts;
    my $method = "do_$self->{command}";
    die usage() unless $self->can($method);
    $self->$method;
}

sub do_generate {
    my ($self) = @_;
    my @modules = @{$self->{args}};
    die "'generate' requires at least one module name to generate\n"
        unless @modules >= 1;
    # Check module names first:
    for my $module (@modules) {
        die "Invalid module name '$module'"
            unless $module =~ /^[A-Za-z]\w*(?:::[A-Za-z]\w*)*$/;
    }
    # Generate requested modules:
    for my $module (@modules) {
        my $filepath = $self->write_proxy_module('lib', $module);
        print "Inline module '$module' generated as '$filepath'\n";
    }
}

sub import {
    my $class = shift;

    return $class->dist_setup()
        if @_ == 1 and $_[0] eq 'dist';

    return unless @_;

    my ($inline_module) = caller;

    # XXX 'exit' is used to get a cleaner error msg.
    # Try to redo this without 'exit'.
    $class->check_api_version($inline_module, @_)
        or exit 1;

    my $importer = sub {
        require File::Path;
        File::Path::mkpath('./blib') unless -d './blib';
        # TODO try to not use eval here:
        eval "use Inline Config => " .
            "directory => './blib', " .
            "name => '$inline_module'";

        my $class = shift;
        Inline->import_heavy(@_);
    };
    no strict 'refs';
    *{"${inline_module}::import"} = $importer;
}

sub check_api_version {
    my ($class, $inline_module, $api_version, $inline_module_version) = @_;
    if ($api_version ne 'v1' or $inline_module_version ne $VERSION) {
        warn <<"...";
It seems that '$inline_module' is out of date.

Make sure you have the latest version of Inline::Module installed, then run:

    perl-inline-module generate $inline_module

...
        return;
    }
    return 1;
}

sub get_opts {
    my ($self) = @_;
    my $argv = $self->{argv};
    die usage() unless @$argv >= 1;
    my ($command, @args) = @$argv;
    $self->{command} = $command;
    $self->{args} = \@args;
    delete $self->{argv};
}

sub usage {
    <<'...';
Usage:
        perl-inline-module <command> [<arguments>]

Commands:
        perl-inline-module generate Module::Name::Inline

...
}

sub dist_setup {
    my ($class) = @_;
    my ($distdir, $module) = @ARGV;
    $class->write_dyna_module("$distdir/lib", $module);
    $class->write_proxy_module("$distdir/inc", $module);
}

sub write_proxy_module {
    my ($class, $dest, $module) = @_;

    my $code = <<"...";
# DO NOT EDIT
#
# GENERATED BY: Inline::Module $Inline::Module::VERSION
#
# This module is for author-side development only. When this module is shipped
# to CPAN, it will be automagically replaced with content that does not
# require any Inline framework modules (or any other non-core modules).

use strict; use warnings;
package $module;
use base 'Inline';
use Inline::Module 'v1' => '$VERSION';

1;
...

    $class->write_module($dest, $module, $code);
}

sub write_dyna_module {
    my ($class, $dest, $module) = @_;
    my $code = <<"...";
# DO NOT EDIT
#
# GENERATED BY: Inline::Module $Inline::Module::VERSION

use strict; use warnings;
package $module;
use base 'DynaLoader';
bootstrap $module;

1;
...

# XXX - think about this later:
# our \$VERSION = '0.0.5';
# bootstrap $module \$VERSION;

    $class->write_module($dest, $module, $code);
}

sub write_module {
    my ($class, $dest, $module, $text) = @_;

    my $filepath = $module;
    $filepath =~ s!::!/!g;
    $filepath = "$dest/$filepath.pm";
    my $dirpath = $filepath;
    $dirpath =~ s!(.*)/.*!$1!;
    File::Path::mkpath($dirpath);

    open OUT, '>', $filepath
        or die "Can't open '$filepath' for output:\n$!";
    print OUT $text;
    close OUT;

    return $filepath;
}

1;
