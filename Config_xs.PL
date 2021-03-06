#!/usr/bin/perl
#
# Regenerate (overwriting only if changed):
#
#    lib/Config.pm
#    lib/Config_heavy.pl
#    lib/Config.pod
#    ext/Config/Config_xs.in
#    ext/Config/Config_xs.out
#    ext/Config/Config.xs
#
# from the contents of the static files
#
#    ext/Config/Config_xs.in (the gperf template)
#
# and from the contents of the Configure-generated file
#
#    lib/Config_heavy.pl
#    lib/Config_git.pl
#

$VERSION = '6.00_04';
my $in_core;

BEGIN {
    unless(-d 'regen') {
        require '../../regen/regen_lib.pl';
        $in_core = 1;
    } else {
        require 'regen/regen_lib.pl';
    }
    my $ptrsize = length(pack('P',""));
    my $ivsize =  length(pack('j',0));
    die "unknown pointer size" if $ptrsize != 4 && $ptrsize != 8; #POSIX.pm not available
    eval 'sub SPTR_MIN () { '.($ptrsize == 8 ? '-9223372036854775808' : '-2147483648').' } '.
    'sub SPTR_MAX () { '.($ptrsize == 8 ? '0x7FFFFFFFFFFFFFFF' : '0x7FFFFFFF').' } '.
    'sub IV_MIN () { '.($ivsize == 8 ? '-9223372036854775808' : '-2147483648').' } '.
    'sub IV_MAX () { '.($ivsize == 8 ? '0x7FFFFFFFFFFFFFFF' : '0x7FFFFFFF').' } ';
}
use strict ;
use Config ;

###########################################################################

my $force = @ARGV ? $ARGV[0] eq '--force' : 0;
shift if $force;
my $no_gperf = @ARGV ? $ARGV[0] eq '--no-gperf' : 0;
shift if $no_gperf;
my $heavy = searchdirs('Config_heavy.pl', \@INC);
my $git   = searchdirs('Config_git.pl', \@INC);
# the key-only gperf syntax template with empty values, this is where to fix XSUBs
my $xsin  = 'Config_xs.in';
# gperf expanded canned template with empty values, a generated file
my $xsout = 'Config_xs.out';
# gperf expanded build specific template with empty values, a generated file
my $xsoutcustm = 'Config_xs.tmp.out';
# patched with our values, a generated file
my $xstarg= 'Config.xs';

my ($in, $xs, %h, $gperf_ok);

# collect all the values.
# and check if any keys had changed. need to update the gperf then.
if ($in_core && ! -e $heavy) { # help the Makefile deps to produce Config_heavy.pl
    system("$^X -Ilib configpm");
}
open $in, "<", $heavy or die "Error reading '$heavy': $!";
while (<$in>) {
    last if $_ eq "\$_ = <<'!END!';\n";
}
while (<$in>) { # as in config.sh
    chomp;
    last if $_ eq '!END!';
    next if /^perl_(version|subversion|revision)=/;
    my ($k,$v) = split(/=/,$_,2);
    $v = substr($v, 1, length($v)-2);#strip start/end quotes, ' or "
    #$v =~ s/\\/\\\\/g;
    $h{$k} = $v;
}
while (<$in>) {
    last if $_ eq "our \$Config_SH_expanded = \"\\n\$_\" . << 'EOVIRTUAL';\n";
}
while (<$in>) {
    chomp;
    last if $_ eq 'EOVIRTUAL';
    my ($k,$v) = split(/=/,$_,2);
    $v = substr($v, 1, length($v)-2);#strip start/end quotes, ' or "
    #$v =~ s/\\/\\\\/g;
    $h{$k} = $v;
}
close $in;
if ($in_core || -e $git) {
    open $in, "<", $git or die "Error reading '$git': $!";
    while (<$in>) {
        last if $_ eq "\$Config::Git_Data=<<'ENDOFGIT';\n";
    }
    while (<$in>) {
        chomp;
        last if $_ eq 'ENDOFGIT';
        my ($k,$v) = split(/=/,$_,2);
        $v = substr($v, 1, length($v)-2);#strip start/end quotes, ' or "
        $h{$k} = $v;
    }
    close $in;
}

# Test if gperf works. if not patch canned xsout instead.
unless ($no_gperf) {
    local $!;
    $gperf_ok = !(system("gperf --output-file=${xsout}_tmp $xsin") >> 8);
    if ($gperf_ok and -z $xsout."_tmp") {
        $gperf_ok = 0;
    }
    unlink $xsout."_tmp";
    print STDERR "gperf ",$gperf_ok ? "works ok\n" : "does not work\n";
    if ($gperf_ok) {
#diag http://cpantesters.org/cpan/report/e334bb42-a77e-11e5-9410-f17aaf845ad4
        unless ($in_core) {
            require Data::Dumper;
            print Data::Dumper::Dumper(\%ENV);
            print `gperf -v`;
        }
    } else {
        local $/;
        my $msg = <DATA>;
        eval $msg;
    }
}

if ($gperf_ok) {
    #make a customized .xs, not git tracked, smaller Config shared lib since
    #we dont need a "universal" set of keys for all build configs of perl
    gen_gperf_Config($xsin, $xsoutcustm, \%h);
    # postprocess the values a bit to generate a canned Config for CI/no gperf
    # reserve up to 20 config_args
    for (0..20) {
        my $k = "config_arg".$_;
        $h{$k} = '' unless exists $h{$k};
    }
    my @cannedkeys =
               qw(  bin_ELF bootstrap_charset canned_gperf ccstdflags ccwarnflags
                    charsize config_argc config_args d_re_comp d_regcmp git_ancestor
                    git_remote_branch git_unpushed hostgenerate hostosname hostperl
                    incpth installhtmldir installhtmlhelpdir ld_can_script
                    libdb_needs_pthread mad malloc_cflags sysroot targetdir
                    targetenv targethost targetmkdir targetport
                    useversionedarchname);
    unless ($in_core) { #cperl doesn't need these, CPAN does
        push @cannedkeys , qw(
d_acosh d_asinh d_atanh d_backtrace d_builtin_arith_overflow    d_cbrt
d_copysign  d_dladdr    d_erf   d_erfc  d_exp2  d_expm1 d_fdim  d_fegetround
d_fma   d_fmax  d_fmin  d_fp_classify   d_fp_classl d_fpgetround    d_fs_data_s
d_fstatfs   d_fstatvfs  d_getfsstat d_getmnt    d_getmntent d_hasmntopt d_hypot
d_ilogb d_ip_mreq   d_ip_mreq_source    d_ipv6_mreq d_ipv6_mreq_source
d_isblank   d_isfinitel d_isinfl    d_isless    d_isnormal  d_j0    d_j0l
d_lc_monetary_2008  d_ldexpl    d_lgamma    d_lgamma_r  d_libname_unique
d_llrint    d_llrintl   d_llround   d_llroundl  d_log1p d_log2  d_logb  d_lrint
d_lrintl    d_lround    d_lroundl   d_nan   d_nearbyint d_nextafter
d_nexttoward    d_prctl d_prctl_set_name    d_ptrdiff_t d_regcomp   d_remainder
d_remquo    d_rint  d_round d_scalbn    d_sfio  d_sin6_scope_id d_sockaddr_in6
d_sockaddr_sa_len   d_stat  d_statfs_f_flags    d_statfs_s  d_static_inline
d_statvfs   d_tgamma    d_trunc d_truncl    d_ustat
d_vms_case_sensitive_symbols    d_wcscmp    d_wcsxfrm   defvoidused
dl_so_eq_ext    dlltool doubleinfbytes  doublekind  doublemantbits
doublenanbytes  found_libucb    git_commit_date hash_func   i_bfd   i_dld
i_execinfo  i_fenv  i_mntent    i_quadmath  i_sfio  i_stdbool   i_stdint
i_sysmount  i_sysstatfs i_sysstatvfs    i_sysvfs    i_ustat ieeefp_h
longdblinfbytes longdblkind longdblmantbits longdblnanbytes madlyh  madlyobj
madlysrc    nvmantbits  perl_static_inline  st_ino_sign st_ino_size targetsh
usecbacktrace   usecperl    usekernprocpathname usensgetexecutablepath
usequadmath usesfio voidflags
        );
    }

    for my $k (@cannedkeys) {
        $h{$k} = '' unless exists $h{$k};
    }
    gen_gperf_Config($xsin, $xsout, \%h); #generate git tracked
    $xsout = $xsoutcustm; #use smaller build specific .xs
}

#code in Config_heavy.pl to compute byteorder is customized/interpolated
#for each build permutation of perl by configpm, the byteorder in the
#Config_heavy.pl database is ignored, just use Config_heavy.pl to get byteorder
#instead of copying the complicated code in configpm to here
$h{byteorder} = $Config{byteorder};

# and now patch the values into Config.xs
open $in, '<', $xsout  or die "Error reading '$xsout': $!";
open $xs, '>', $xstarg or die "Error writing '$xstarg': $!";
while (<$in>) {
    if (/0,"@@(\w+)@@"/) {
        my $k = $1;
        my $v = $h{$k};
        my $type = t_type($v);
        my ($qv, $l);
        if ($type eq 'T_STR') {
          if ($v eq 'define') {
            $l  = 0;
            $qv = 'VDEFINE'
          } elsif ($v eq 'undef') {
            $l  = 0;
            $qv = 'VUNDEF'
          } elsif ($v eq '') {
            $l  = 0;
            $qv = 'VEMPTY'
          } else { # a regular C string
            die "the value of Config key $k is over permitted length"
              unless length($v) <= 1<<16;
            $v =~ s/"/\\"/g;
            # $v =~ s/\\!/!/;
            # $v =~ s/\\ / /g;
            $qv = $v;
            $qv =~ s/(\\[^nrftacx"' ])/\\$1/g; # windows paths: \\ => \\\\
            $qv =~ s/(\\[nrftacx ])/\\$1/g;  # \n => \\n, allowed escape chars
            $qv = '"'.$qv.'"';
            $l = $v =~ m/["'\\]/ ?
            # don't calculate C-style length [cperl #61], let C do it for us
            # and don't count the ending \0
              'sizeof (' . $qv . ')-1'
              : length($v)+0;
          }
        } else { # $type eq 'T_INT'
          if ($v >= SPTR_MIN && $v <= SPTR_MAX) { #can fit in a ptr
            $l = 0;
            $qv = '(char *)'.$v;
          } else {#str in C, IV in perl, will be atoi-ed, 64b IV on 32b perl
            $l = length($v);
            $qv = '"'.$v.'"';
          }
        }
        my $new = $type.', '. $l . ', ' . $qv ;
        s/T_\w+,	0,"\@\@$k\@\@"/$new/; # we have one line per key only
        chomp;
        print $xs $_, " /* $k */\n";
    } else {
        print $xs $_;
    }
}
close $in;
close $xs;
rename $xsout."_tmp", $xsout;

#creates a not-valid-C/XS template for gperf, then runs it through gperf, then
#fixes misc flaws in the C code gen of gperf in the C/XS file, the final
#C/XS file has all the Config keys, but no Config values
sub gen_gperf_Config {
    my $in;
    my ($xsin, $xsout, $h) = @_;
    my $xs = open_new($xsin, '>');
    open $in, "<", $xsin or die "Error reading '$xsin': $!";

    # expand only keys within %%
    while (<$in>) {
        print $xs $_;
        last if /^%%$/;
    }

    foreach my $k (sort { $a cmp $b } keys %$h) {
        my $tabs = "\t" x (3-((2+length($k))/8));
        #generate gperf syntax section of Config_xs.in
        printf $xs "%s,\t%s%s,\t0,\"@@%s@@\"\n", $k, $tabs, 'T_INV', $k;
    }
    print $xs "%%\n";

    while (<$in>) {
        last if /^%%$/;
    }
    # and the rest after the keys
    while (<$in>) {
        print $xs $_;
    }
    close $in;
    $xs->flush if $xs->can('flush');

    if (close_and_rename($xs) or $force or -M $xsin < -M $xsout or !(-f $xsout))
    {
        die "file $xsin is zero bytes long" if -s $xsin == 0;
        my $run = "gperf --output-file=$xsout $xsin";
#diag http://cpantesters.org/cpan/report/4f74a142-a7ce-11e5-9426-d789aef69d38
        print STDERR 'will run |||'.$run."|||\n";
        system($run);
        if (-s $xsout == 0) {
            warn "$xsout is zero bytes long\nnow dumping $xsin\n\n***************************\n";
            open(my $xsinfh, "<", $xsin) or die $!;
            local $/; # enable localized slurp mode
            my $xsindata = <$xsinfh>;
            close $xsinfh;
            warn $xsindata;
            warn "\n***************************\n";
        }
        post_process_gperf($xsout);
    }
}

sub post_process_gperf {
  my $in = shift;
  my $tmp = $in.".tmp";
  open my $OUT, '>', $tmp or die "Can't write '$tmp': $!";
  binmode $OUT;
  local $/ = "\n\n";
  print $OUT <<'EOT';
/* ex: set ro ft=c: -*- buffer-read-only: t; mode: c; c-basic-offset: 4; -*-
  !!!!!!!   DO NOT EDIT THIS FILE   !!!!!!!
  This file is built by ext/Config/Config_xs.PL and ext/Config/Config_xs.in. */
EOT
  my $lnr = 0;
  open my $IN, '<', $in or die "Can't read '$in': $!";

  while (<$IN>) {
    # overlong line, and don't bother bug-gnu-gperf\@gnu.org with crazy encodings
    # also c_indent.t
    # XXX add EBCDIC support, bypassing gperf (i.e. pperf)
    s/^#?error "gperf generated tables don't work with this execution character set. Please report a bug to <bug-gnu-gperf\@gnu.org>."/#  error "gperf generated tables don't work with this non ISO-646 based character set."/m;

    # C++ requires full struct initializers
    s/{-1},/{XCNAME_MAX, 1, 0, NULL},/g;

    # skip inline
    s/\Q#ifdef __GNUC__
__inline
#if defined __GNUC_STDC_INLINE__ || defined __GNUC_GNU_INLINE__
__attribute__ ((__gnu_inline__))
#endif
#endif\E//;
    s/\Q#ifdef __GNUC__
__inline
#else
#ifdef __cplusplus
inline
#endif
#endif\E//;
    s/\Q#if (defined (__STDC_VERSION__) && __STDC_VERSION__ >= 199901L) || defined(__cplusplus) || defined(__GNUC_STDC_INLINE__)
inline
#elif defined(__GNUC__)
__inline
#endif
\E//;

    # There should be at least one space between a C keyword and any subsequent
    # open parenthesis
    s/sizeof\(/sizeof (/g;

    # fixup U16
    s/\(int\)\(long\)\&/(U16)(long)&/g;
    s/\Qregister int o = wordlist[key].name\E/register U16 o = wordlist[key].name/;
    s/\Qif (o >= 0)\E\n/if (o != XCNAME_MAX)\n/;

    # don't delete line numbers, pointing to Config_xs.in
    # s/^#line \d+ .+$//gm;
    # but insert a #line after the wordlist in Config_lookup
    $lnr += tr/\n/\n/;
    if (/if \(len <= MAX_WORD_LENGTH/) {
      print $OUT "#line $lnr \"Config.xs\"\n";
    }

    print $OUT $_;
  }
  close $IN;
  close $OUT;
  rename $tmp, $in;
}

sub t_type ($) {
    my $v = shift;
    if ($v =~ /^-?\d+$/ && $v >= IV_MIN && $v <= IV_MAX) {
        return 'T_INT';
    } else {
        return 'T_STR';
    }
}

sub searchdirs {
    my($fn, $fullfn) = shift;
    foreach my $d ( @{$_[0]} ) {
        my $tmppath = $d.'/'.$fn;
        if (-s $tmppath) {
            $fullfn = $tmppath;
            last;
        }
    }
    return $fullfn;
}
__DATA__

#Generated with Font ANSI Shadow
#http://patorjk.com/software/taag/#p=display&f=ANSI%20Shadow&t=please%0Ainstall%0Agperf%20for%0Aefficiency%0Aand%0Arebuild

my $utf8msg =
'██████╗ ██╗     ███████╗ █████╗ ███████╗███████╗
██╔══██╗██║     ██╔════╝██╔══██╗██╔════╝██╔════╝
██████╔╝██║     █████╗  ███████║███████╗█████╗
██╔═══╝ ██║     ██╔══╝  ██╔══██║╚════██║██╔══╝
██║     ███████╗███████╗██║  ██║███████║███████╗
╚═╝     ╚══════╝╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝

██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗
██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║
██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║
██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║
██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝

 ██████╗ ██████╗ ███████╗██████╗ ███████╗    ███████╗ ██████╗ ██████╗
██╔════╝ ██╔══██╗██╔════╝██╔══██╗██╔════╝    ██╔════╝██╔═══██╗██╔══██╗
██║  ███╗██████╔╝█████╗  ██████╔╝█████╗      █████╗  ██║   ██║██████╔╝
██║   ██║██╔═══╝ ██╔══╝  ██╔══██╗██╔══╝      ██╔══╝  ██║   ██║██╔══██╗
╚██████╔╝██║     ███████╗██║  ██║██║         ██║     ╚██████╔╝██║  ██║
 ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝         ╚═╝      ╚═════╝ ╚═╝  ╚═╝

███████╗███████╗███████╗██╗ ██████╗██╗███████╗███╗   ██╗ ██████╗██╗   ██╗
██╔════╝██╔════╝██╔════╝██║██╔════╝██║██╔════╝████╗  ██║██╔════╝╚██╗ ██╔╝
█████╗  █████╗  █████╗  ██║██║     ██║█████╗  ██╔██╗ ██║██║      ╚████╔╝
██╔══╝  ██╔══╝  ██╔══╝  ██║██║     ██║██╔══╝  ██║╚██╗██║██║       ╚██╔╝
███████╗██║     ██║     ██║╚██████╗██║███████╗██║ ╚████║╚██████╗   ██║
╚══════╝╚═╝     ╚═╝     ╚═╝ ╚═════╝╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝   ╚═╝

 █████╗ ███╗   ██╗██████╗
██╔══██╗████╗  ██║██╔══██╗
███████║██╔██╗ ██║██║  ██║
██╔══██║██║╚██╗██║██║  ██║
██║  ██║██║ ╚████║██████╔╝
╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝

██████╗ ███████╗██████╗ ██╗   ██╗██╗██╗     ██████╗
██╔══██╗██╔════╝██╔══██╗██║   ██║██║██║     ██╔══██╗
██████╔╝█████╗  ██████╔╝██║   ██║██║██║     ██║  ██║
██╔══██╗██╔══╝  ██╔══██╗██║   ██║██║██║     ██║  ██║
██║  ██║███████╗██████╔╝╚██████╔╝██║███████╗██████╔╝
╚═╝  ╚═╝╚══════╝╚═════╝  ╚═════╝ ╚═╝╚══════╝╚═════╝
';

my $cp437msg =
'�����ۻ �ۻ     ������ۻ ����ۻ ������ۻ������ۻ
������ۻ�ۺ     ������ͼ������ۻ������ͼ������ͼ
������ɼ�ۺ     ����ۻ  ������ۺ������ۻ����ۻ
�����ͼ �ۺ     ����ͼ  ������ۺ������ۺ����ͼ
�ۺ     ������ۻ������ۻ�ۺ  �ۺ������ۺ������ۻ
�ͼ     ������ͼ������ͼ�ͼ  �ͼ������ͼ������ͼ

�ۻ��ۻ   �ۻ������ۻ�������ۻ ����ۻ �ۻ     �ۻ
�ۺ���ۻ  �ۺ������ͼ�������ͼ������ۻ�ۺ     �ۺ
�ۺ����ۻ �ۺ������ۻ   �ۺ   ������ۺ�ۺ     �ۺ
�ۺ�ۺ��ۻ�ۺ������ۺ   �ۺ   ������ۺ�ۺ     �ۺ
�ۺ�ۺ ����ۺ������ۺ   �ۺ   �ۺ  �ۺ������ۻ������ۻ
�ͼ�ͼ  ���ͼ������ͼ   �ͼ   �ͼ  �ͼ������ͼ������ͼ

 �����ۻ �����ۻ ������ۻ�����ۻ ������ۻ    ������ۻ �����ۻ �����ۻ
������ͼ ������ۻ������ͼ������ۻ������ͼ    ������ͼ�������ۻ������ۻ
�ۺ  ��ۻ������ɼ����ۻ  ������ɼ����ۻ      ����ۻ  �ۺ   �ۺ������ɼ
�ۺ   �ۺ�����ͼ ����ͼ  ������ۻ����ͼ      ����ͼ  �ۺ   �ۺ������ۻ
�������ɼ�ۺ     ������ۻ�ۺ  �ۺ�ۺ         �ۺ     �������ɼ�ۺ  �ۺ
 �����ͼ �ͼ     ������ͼ�ͼ  �ͼ�ͼ         �ͼ      �����ͼ �ͼ  �ͼ

������ۻ������ۻ������ۻ�ۻ �����ۻ�ۻ������ۻ��ۻ   �ۻ �����ۻ�ۻ   �ۻ
������ͼ������ͼ������ͼ�ۺ������ͼ�ۺ������ͼ���ۻ  �ۺ������ͼ��ۻ ��ɼ
����ۻ  ����ۻ  ����ۻ  �ۺ�ۺ     �ۺ����ۻ  ����ۻ �ۺ�ۺ      �����ɼ
����ͼ  ����ͼ  ����ͼ  �ۺ�ۺ     �ۺ����ͼ  �ۺ��ۻ�ۺ�ۺ       ���ɼ
������ۻ�ۺ     �ۺ     �ۺ������ۻ�ۺ������ۻ�ۺ ����ۺ������ۻ   �ۺ
������ͼ�ͼ     �ͼ     �ͼ �����ͼ�ͼ������ͼ�ͼ  ���ͼ �����ͼ   �ͼ

 ����ۻ ��ۻ   �ۻ�����ۻ
������ۻ���ۻ  �ۺ������ۻ
������ۺ����ۻ �ۺ�ۺ  �ۺ
������ۺ�ۺ��ۻ�ۺ�ۺ  �ۺ
�ۺ  �ۺ�ۺ ����ۺ������ɼ
�ͼ  �ͼ�ͼ  ���ͼ�����ͼ

�����ۻ ������ۻ�����ۻ �ۻ   �ۻ�ۻ�ۻ     �����ۻ
������ۻ������ͼ������ۻ�ۺ   �ۺ�ۺ�ۺ     ������ۻ
������ɼ����ۻ  ������ɼ�ۺ   �ۺ�ۺ�ۺ     �ۺ  �ۺ
������ۻ����ͼ  ������ۻ�ۺ   �ۺ�ۺ�ۺ     �ۺ  �ۺ
�ۺ  �ۺ������ۻ������ɼ�������ɼ�ۺ������ۻ������ɼ
�ͼ  �ͼ������ͼ�����ͼ  �����ͼ �ͼ������ͼ�����ͼ
';
#appveyor's console->html converter assumes console output is utf8 even though
#console is set to CP 437
print $^O eq 'MSWin32' && ! $ENV{APPVEYOR} ? $cp437msg : $utf8msg;
