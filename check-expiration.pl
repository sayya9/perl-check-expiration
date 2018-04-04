#!/usr/bin/perl
# Andrew

use strict;
use warnings;
use Net::SMTP;
use Sys::Hostname;
use Time::Piece;

my @FilerList;
my @NetList;
my @AllOldProjList;
my @AllEmptyVolList;
my @AllOfflineVolList;
my @AllMailContent;
my $Domain = &IdentifyDomain;

@FilerList = &GenFilerList($Domain);
@NetList = &GenVolList($Domain, @FilerList);
@AllOldProjList = &GenOldProjList(@NetList);
@AllEmptyVolList = &GenEmptyVolList(@NetList);
@AllOfflineVolList = &GenOfflineVolList(@FilerList);
@AllMailContent = &GenMailContent(\@AllOldProjList, \@AllEmptyVolList, \@AllOfflineVolList);
if(@AllMailContent) {
    &TransferMail($Domain, @AllMailContent);
}

sub IdentifyDomain {
    my $Name = `nisdomainname`;

    if($Name =~ /^tw\n*$/) {
        return 'nistw';
    }
    elsif($Name =~ /^us\n*$/) {
        return 'nisus';
    }
    else {
        print "Can't lookup domain availability\n";
        exit 1;
    }
}

sub GenFilerList {
    my @FilerList;

    open my $f, "/etc/hosts" or die "$0: open file: $!";
    if($_[0] eq "nistw") {
        while(<$f>) {
            if(/^.*\s+(twnas\d+).*nistw.*NAS\s*$/) {
                push @FilerList, $1;
            }
        }
    }
    elsif($_[0] eq "nisus") {
        while(<$f>) {
            if(/^.*\s+(usnas\d+).*nisus.*NAS\s*$/) {
                push @FilerList, $1;
            }
        }
    }
    close $f;
    return @FilerList;
}

sub GenVolList {
    my($Domain, @FilerList) = @_;
    my @NetList;

    foreach(@FilerList) {
        my $Filer = "/net/$_";
        my @VolumeList = `/usr/bin/rsh $_ df -h`;

        foreach(@VolumeList) {
            (! /snap|vol0|File/ and /^(.*?)\s+.*/) ? push @NetList, "$Filer$1" : next;
        }
    }

    if($Domain eq 'nistw') {
        my $SONAS0 = "/net/sonas/nistw";
        my $SONAS1 = "/net/sonas/nistw";
        @NetList = (@NetList, "${SONAS0}/project/*", "${SONAS0}/project2/*",
            "${SONAS0}/project3/*", "${SONAS0}/project4/*", "${SONAS0}/project5/*",
            "${SONAS0}/home", "${SONAS0}/misc/group", "${SONAS1}/project/*",
            "${SONAS1}/home", "${SONAS1}/misc/group");
    }
    elsif($Domain eq 'nisus') {
        @NetList = (@NetList);
    }
    return @NetList;
}

sub GenOldProjList {
    my $Date;
    my $IsRight;
    my @NetList = @_;
    my @Temp;
    my @AllOldProjList;

    foreach(@NetList) {
        push @Temp, `find $_ -noleaf -maxdepth 1 -mindepth 1 \! -name '*snapshot*' -type d`;
    }

    foreach(@Temp) {
        if(/.*-(?:migration|archive|terminate)-(.*)-(.*)-(.*)/) {
            my $Format1 = "%a %b %d %H:%M:%S %Y";
            my $Format2 = "%m %d %H:%M:%S %Y";
            my $Now = localtime;
            my $DataTime = $2 . " " . $3 . " " . "00:00:00 " . $1;
            my $Diff = Time::Piece->strptime($Now->cdate, $Format1) -
                    Time::Piece->strptime($DataTime, $Format2);
            if($Diff > 0) {
                push @AllOldProjList, $_;
            }
            chomp(@AllOldProjList);
        }
    }
    return @AllOldProjList;
}

sub GenEmptyVolList {
    my $IsRight;
    my @AllEmptyVolList;

    foreach(@NetList) {
        $IsRight = `ls -a $_ | grep -v ".snapshot" | wc -l`;
        if($IsRight =~ /^2$/) {
            push @AllEmptyVolList, $_;
        }
    }
    return @AllEmptyVolList;
}

sub GenOfflineVolList {
    my @Temp;
    my @AllOfflineVolList;

    foreach my $FilerList (@FilerList) {
        @Temp = `/usr/bin/rsh $FilerList vol status`;
        foreach(@Temp) {
            if(/\s*(.*?)\s+.*offline/) {
                push @AllOfflineVolList, "$FilerList: $1"
            }
        }
    }
    return @AllOfflineVolList;
}

sub GenMailContent {
    my($AllOldProjList, $AllEmptyVolList, $AllOfflineVolList) = @_;
    my @AllMailContent;

    if(@{$AllOldProjList}) {
        push @AllMailContent, "Old project/Archive account/Terminated account:\n";
        foreach(@{$AllOldProjList}) {
            push @AllMailContent, "$_\n";
        }
        push @AllMailContent, "\n\n\n";
    }

    if(@{$AllEmptyVolList}) {
        push @AllMailContent, "Empty volume:\n";
        foreach(@{$AllEmptyVolList}) {
            push @AllMailContent, "$_\n";
        }
        push @AllMailContent, "\n\n\n";
    }

    if(@{$AllOfflineVolList}) {
        push @AllMailContent, "Offline volume:\n";
        foreach(@{$AllOfflineVolList}) {
            push @AllMailContent, "$_\n";
        }
        push @AllMailContent, "\n\n\n";
    }
    return @AllMailContent;
}

sub TransferMail {
    my $hostname = hostname;
    my $smtp;
    my $subject = "[Info] Daily volume of check report!!";
    my ($Domain, @AllMailContent) = @_;
    my @mailto;
    my $n = "Please support to check below data\n\n";
    
    if($Domain eq "nistw") {
        $smtp = Net::SMTP->new('smtpserver') or die 'die';
        #@mailto = ("vend.andrew.lo\@mediatek.com");
        @mailto = ("andrew\@example.com", "arthur\@example.com");
                
    }
    elsif($Domain eq "nisus") {
        $smtp = Net::SMTP->new('smtp.mediatek.inc') or die 'die';
        @mailto = ("andrew\@example.com", "erica\@example.com");
    }
    $smtp->mail("$hostname\@example.com");
    $smtp->to(@mailto);
    $smtp->data();
    $smtp->datasend("Subject: $subject\n");
    $smtp->datasend("To: " . join(';', @mailto) . "\n");
    $smtp->datasend("\n");
    $smtp->datasend($n);
    foreach(@AllMailContent) {
        $smtp->datasend("$_");
    }
    $smtp->dataend();
    $smtp->quit;
}
