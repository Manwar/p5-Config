#!/usr/bin/perl

if (scalar keys %Config:: > 2) {
  print "0..1 #SKIP Cannot test with static or builtin Config\n";
  exit;
}

require Config; #this is supposed to be XS config
require B;

*isXSUB = !B->can('CVf_ISXSUB')
  ? sub { shift->XSUB }
  : sub { shift->CvFLAGS & B::CVf_ISXSUB() }; #CVf_ISXSUB added in 5.9.4

#is_deeply->overload.pm wants these 2 XS modules
#can't be required once DynaLoader is removed later on
require Scalar::Util;
eval { require mro; };
my $cv = B::svref_2object(*{'Config::FETCH'}{CODE});
unless (isXSUB($cv)) {
  if (-d 'regen') { #on CPAN
    warn "Config:: is not XS Config";
  } else {
    print "0..1 #SKIP Config:: is not XS Config, miniperl?\n";
    exit;
  }
}

my $in_core = ! -d "regen";

# change the class name of XS Config so there can be XS and PP Config at same time
foreach (qw( TIEHASH DESTROY DELETE CLEAR EXISTS NEXTKEY FIRSTKEY KEYS SCALAR FETCH)) {
  *{'XSConfig::'.$_} = *{'Config::'.$_}{CODE};
}
tie(%XSConfig, 'XSConfig');

# delete package
undef( *main::Config:: );
require Data::Dumper;
$Data::Dumper::Useperl = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Useqq = 0;
$Data::Dumper::Quotekeys = 0;

# full perl is now miniperl
undef( *main::XSLoader::);
require 'Config_mini.pl';
Config->import();
require 'Config_heavy.pl';
require Test::More;
Test::More->import (tests => 4);

ok(isXSUB($cv), 'XS Config:: is XS');

$cv = B::svref_2object(*{'Config::FETCH'}{CODE});
ok(!isXSUB($cv), 'PP Config:: is PP');

my $klenXS = scalar(keys %XSConfig);
my $copy = 0;
my %Config_copy;
if (exists $XSConfig{canned_gperf}) { #fix up PP Config to look like XS Config
  #to see in CPAN Testers reports if the builder had gperf or not
  warn "This XS Config was built with the canned XS file\n";
  $copy = 1;
  for (keys %Config) {
    $Config_copy{$_} = $Config{$_};
  }
  # See Config_xs.PL:
  # postprocess the values a bit:
  # reserve up to 20 config_args
  for (0..20) {
    my $k = "config_arg".$_;
    $Config_copy{$k} = '' unless exists $Config{$k};
  }
  my @cannedkeys =
            qw( bin_ELF bootstrap_charset canned_gperf ccstdflags ccwarnflags
                charsize config_argc config_args d_re_comp d_regcmp git_ancestor
                git_remote_branch git_unpushed hostgenerate hostosname hostperl
                incpth installhtmldir installhtmlhelpdir ld_can_script
                libdb_needs_pthread mad malloc_cflags sysroot targetdir
                targetenv targethost targetmkdir targetport
                useversionedarchname);
  unless($in_core) { #cperl doesn't need these, CPAN does
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
    $Config_copy{$k} = '' unless exists $Config{$k};
  }
  is (scalar keys %Config_copy, $klenXS, 'same adjusted key count');
} else {
  is (scalar(keys %Config), $klenXS, 'same key count');
}

is_deeply ($copy ? \%Config_copy : \%Config, \%XSConfig, "cmp PP to XS hashes");

if (!Test::More->builder->is_passing()) {
# 2>&1 because output string not captured on solaris
# http://cpantesters.org/cpan/report/fa1f8f72-a7c8-11e5-9426-d789aef69d38
  my $diffout = `diff --help 2>&1`;
  if (index($diffout, 'Usage: diff') != -1 #GNU
      || index($diffout, 'usage: diff') != -1) { #Solaris
    open my $f, '>','xscfg.txt';
    print $f Data::Dumper::Dumper({%XSConfig});
    close $f;
    open my $g, '>', 'ppcfg.txt';
  
    print $g ($copy
              ? Data::Dumper::Dumper({%Config_copy})
              : Data::Dumper::Dumper({%Config}));
    close $g;
    system('diff -U 0 ppcfg.txt xscfg.txt > cfg.diff');
    unlink('xscfg.txt');
    unlink('ppcfg.txt');
    if (-s 'cfg.diff') {
      open my $h , '<','cfg.diff';
      local $/;
      my $file = <$h>;
      close $h;
      diag($file);
    }
    unlink('cfg.diff');
  } else {
    diag('diff not available, can\'t output config delta');
  }
}
