# Configure VirtualBox
# forked from github:boxen/puppet-virtualbox
# Usage:
#   
#   include virtualbox
class seteam_demostack::vbox (
  $version = $seteam_demostack::params::vbox_version,
  $patch_level = $seteam_demostack::params::vbox_patch_level
) inherits seteam_demostack::params {

  exec { 'Kill Virtual Box Processes':
    command     => 'pkill "VBoxXPCOMIPCD" || true && pkill "VBoxSVC" || true && pkill "VBoxHeadless" || true',
    path        => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
    refreshonly => true,
  }

  package { "VirtualBox-${version}-${patch_level}":
    ensure   => present,
    provider => 'pkgdmg',
    source   => "http://download.virtualbox.org/virtualbox/${version}/VirtualBox-${version}-${patch_level}-OSX.dmg",
    require  => Exec['Kill Virtual Box Processes'],
  }
}
