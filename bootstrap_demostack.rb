#!/usr/bin/env ruby
#
#	Install/bootstrap script for seteam_demobuild package.  Script will setup
#	Puppet environment on Mac, and kick off a Puppet run to complete rest of
#	the build.
#
# Version works for all in one package

require 'open-uri'
require 'optparse'
require 'fileutils'

def config_puppet(username)
  # Ensure basic directory structure.  Set up parameters and move Puppet
  # module into place. Populates user parameter.
  # Params:
  # +username+:: user account name that will be placed in params.pp

  FileUtils.mkdir_p($puppet_modulepath) unless File.directory?($puppet_modulepath)
  FileUtils.cp_r($module_name, $puppet_modulepath)
  params_file = "#{$module_path}/manifests/params.pp"
  params_text = File.read(params_file)
  params_update = params_text.gsub(/\$user\ \=\ .*/, "$user = '#{username}'")
  File.open(params_file, 'w') { |file| file.puts params_update }
end

def get_pc1(pkg_name_prefix)
  # Downloads PC1 package to install from Puppet Labs site
  # Params:
  # +pkg_name_prefix+:: Name prefix of package to download

  File.open(pkg_name_prefix + '.dmg', 'wb') do |fo|
    fo.write open($puppet_url_prefix + pkg_name_prefix + '.dmg').read
  end
end

def pkginfo(pkg)
  # Gather all info on packages
  # Params:
  # +pkgs+:: Array of packages to install
  # Returns:
  # +pkgs_info+:: Array of hashes containing all package info

  pkg_hash = {
               'app'       => pkg,
               'installed' => installed?(pkg),
			         'latest'    => get_latest_ver(pkg),
             }
end

def get_latest_ver(pkg)
  # Determine latest published Puppet dmgs from website
  # Params:
  # +pkg+:: Package to lookup
  # Returns:
  # +latest+:: Latest version of a package

  versions = []

  $html_lines.each do |line|
		# Match the version number on the puppet html and pull that out.
	  my_match = /href\="#{pkg}\-(\d\.\d\.\d)\-.*"/.match(line)
    if my_match
      versions.push(my_match[1])
    end
  end

  # This makes assumption that page maintainer is correctly ordering
  # versions
  latest = versions[-1]
end

def installed?(pkg)
  # Find out if package is installed
  # Params:
  # +pkg+:: Package lookup
  # Returns:
  # +boolean+:: If installed or not

  system("pkgutil --packages| grep '^com.puppetlabs.#{pkg}$' 1>/dev/null")
end

def install_pc1(pkg_name_prefix)
  # Install Puppet all-in-one package.
  # Params:
  # +pkg_name_prefix+::

  puts "\nInstalling #{pkg_name_prefix}..."
  system("hdiutil mount #{pkg_name_prefix}.dmg")
  system("installer -package /Volumes/#{pkg_name_prefix}/*installer.pkg -target /")
  puts 'Cleaning up...'
  system("umount /Volumes/#{pkg_name_prefix}")
  system("rm #{pkg_name_prefix}.dmg")
  puts "\n"
end

def uninstall_pkg(pkg_hash)
  # Forcibly remove a package from system.

  return unless pkg_hash['installed']
  puts "Removing #{pkg_hash['app']}."
  # HACK: to clean up files from uninstall but retain configuration files.
  # Should revisit after all in one client is released.
  if pkg_hash['app'] != 'puppet-agent' # For old agents since this left files everywhere
    system("for f in $(pkgutil --only-files --files com.puppetlabs.#{pkg_hash['app']}| 
           grep -v etc); do sudo rm /$f; done")
    system("for d in $(pkgutil --only-dirs --files com.puppetlabs.#{pkg_hash['app']} | 
           grep #{pkg_hash['app']} | grep -v etc | tail -r); do sudo rmdir /$d; done")
  else # Should be all-in-one agent and cleaner to remove
    system('rm -rf /opt/puppetlabs')
    system('rm /usr/bin/facter') if File.exist?('/usr/bin/facter')
    system('rm /usr/bin/hiera') if File.exist?('/usr/bin/hiera')
    system('rm /usr/bin/puppet') if File.exist?('/usr/bin/puppet')
  end
  system("pkgutil --forget com.puppetlabs.#{pkg_hash['app']}")
  puts "\n"
end

def parse_options
  # Use optparse to get options
  # Returns:
  # +options+:: Command line arguments

  ARGV << '-h' if ARGV.empty? # autodisplay help banner if no options
  options = {}
  options[:update] = false
  OptionParser.new do|opts|
    opts.banner = "\nUsage: autodemo.rb -u|--username username\n
                   Note: default behavior is to install all-in-one agent if it isn't already
                   installed.  Also will leave older agent installs alone.  If you want to
                   update ONLY all-in-one agent, please choose '--update'.\n\n"
    options[:username] = nil

    opts.on('-u', '--username USERNAME', 'username is mandatory.') do|u|
      options[:username] = u
    end

    opts.on('--update', 'Update Puppet all-in-one agent. Leave older installs alone.') do
      options[:update] = true
    end

    opts.on('--nuclear', 'Completely wipe out earlier Puppet installs and install latest agent.') do
      options[:nuclear] = true
    end

    opts.on_tail('-h', '--help') do
      puts opts
      puts "\n\n"
      exit
    end
  end.parse!

  if options[:nuclear] && options[:update]
    puts "\n--nuclear and --update are mutually exclusive.  Please choose one or the other.\n\n"
    exit
  end

  unless options[:username]
    puts "\nA username (-u|--username USERNAME) is required!\n\n"
    exit
  end

  options
end

# MAIN
if __FILE__ == $PROGRAM_NAME

  if ENV['USER'] != 'root'
    puts "\nThis script should be run as root.  Exiting...\n\n"
    exit
  end

  $puppet_modulepath = '/etc/puppetlabs/code/environments/production/modules/'
  $module_name = 'seteam_demostack'
  $module_path = "#{$puppet_modulepath}/#{$module_name}"
  $puppet_url_prefix = 'http://downloads.puppetlabs.com/mac/PC1/'
  $pkgs = ['facter', 'hiera', 'puppet', 'puppet-agent']
  $html_lines = `curl --silent #{$puppet_url_prefix}`.split("\n")
  osx_ver = /(^\d+\.\d+)/.match(`sw_vers -productVersion`).to_s
  package_info = []
  options = parse_options

  puts "\n\nBootstrapping Puppet Demo environment..."
  puts "Configuring environment for user #{options[:username]}"
  puts 'Getting Puppet package info on system...'
  $pkgs.each do |pkg|
    package_info.push(pkginfo(pkg))
  end

  puts 'Installing/Updating Puppet packages...' if !package_info[3]['installed'] || (options[:update] || options[:nuclear])

  package_info.each do |pkg|
    uninstall_pkg(pkg)
  end if options[:nuclear]

  uninstall_pkg(package_info[3]) if options[:update]

  # Install Puppet agent if requested or not currently installed
  # Format is: appname- + version- + osx- + osx version- + arch + .dmg
  pkg_name_prefix =  'puppet-agent-' + package_info[3]['latest'] + '-osx-' + osx_ver + '-x86_64'
  get_pc1(pkg_name_prefix) if !package_info[3]['installed'] || (options[:update] || options[:nuclear])
  install_pc1(pkg_name_prefix) if !package_info[3]['installed'] || (options[:update] || options[:nuclear])

  # Set up Puppet directories and put manifests in place
  puts "\nSetting up Puppet environment..."
  config_puppet(options[:username])

  puts "\nInitiating Puppet run..."
  system("/opt/puppetlabs/puppet/bin/puppet apply -e 'include #{$module_name}'")
end
