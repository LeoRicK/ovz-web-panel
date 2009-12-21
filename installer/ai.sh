#!/bin/sh

# global variables
VERSION="0.4"
DOWNLOAD_URL="http://ovz-web-panel.googlecode.com/files/ovz-web-panel-$VERSION.tgz"
RUBYGEMS_URL="http://rubyforge.org/frs/download.php/60718/rubygems-1.3.5.tgz"
RUBY_SQLITE3_CMD="ruby -e \"require 'rubygems'\" -e \"require 'sqlite3/database'\""
LOG_FILE="/tmp/ovz-web-panel.log"
INSTALL_DIR="/opt/ovz-web-panel/"
FORCE=0 # force installation to the same directory
PRESERVE_ARCHIVE=0
AUTOSOLVER=1 # automatic solving of dependencies
AUTOSTART=1 # start panel automatically after installation
DISTRIB_ID=""
DEBUG=0
ERR_FATAL=1

for PARAM in $@; do
  eval $PARAM
done

[ "x$DEBUG" = "x1" ] && set -xv 

log()
{
  echo `date` $1 >> $LOG_FILE
}

puts()
{
  echo $1
  log "$1"
}

puts_separator()
{
  puts "-----------------------------------"
}

puts_spacer()
{
  puts 
}

exec_cmd()
{
  TITLE=$1
  COMMAND=$2
  
  puts "$TITLE $COMMAND"
  `$COMMAND`
}

fatal_error()
{
  puts "Fatal error: $1"
  exit $ERR_FATAL
}

is_command_present()
{
  puts "Checking presence of the command: $1"
  
  CMD=`whereis -b $1 | awk '{ print $2 }'`
  [ -n "$CMD" ] && return 0 || return 1
}

detect_os()
{
  puts "Detecting distrib ID..."

  is_command_present "lsb_release"
  if [ $? -eq 0 ]; then
    puts "LSB info: `lsb_release -a`"
    DISTRIB_ID=`lsb_release -si`
    return 0
  fi
  
  [ -f /etc/redhat-release ] && DISTRIB_ID="RedHat"  
  [ -f /etc/fedora-release ] && DISTRIB_ID="Fedora"
}

resolve_deps()
{
  puts "Resolving dependencies..."

  if [ "$DISTRIB_ID" = "Ubuntu" -o "$DISTRIB_ID" = "Debian" ]; then
    apt-get update
    apt-get -y install ruby rubygems libsqlite3-ruby libopenssl-ruby
  fi
  
  if [ "$DISTRIB_ID" = "RedHat" ]; then
    yum -y install ruby
    is_command_present gem
    if [ $? -ne 0 ]; then
      yum -y install ruby-devel ruby-docs ruby-ri ruby-irb ruby-rdoc
      wget -nc -P /tmp/ $RUBYGEMS_URL
      ARCHIVE_NAME=`echo $RUBYGEMS_URL | sed 's/.\+\///g'`
      DIR_NAME=`echo $ARCHIVE_NAME | sed 's/.tgz//g'`
      tar -C /tmp/ -xzf /tmp/$ARCHIVE_NAME
      ruby /tmp/$DIR_NAME/setup.rb
      rm -f /tmp/$ARCHIVE_NAME
      rm -rf /tmp/$DIR_NAME
    fi   
    
    sh -c "$RUBY_SQLITE3_CMD" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      yum -y install sqlite-devel make gcc
      gem install sqlite3-ruby --version '= 1.2.4'
    fi 
  fi
  
  if [ "$DISTRIB_ID" = "Fedora" ]; then
    yum -y install ruby rubygems ruby-sqlite3
  fi
}

check_environment() {
  puts "Checking environment..."
  
  [ "`whoami`" != "root" ] && fatal_error "Installer should be executed under root user."
  
  puts "System info: `uname -a`"
  
  detect_os
  [ "x$DISTRIB_ID" != "x" ] && puts "Detected distrib ID: $DISTRIB_ID"

  [ "x$AUTOSOLVER" = "x1" ] && resolve_deps

  is_command_present ruby
  if [ $? -eq 0 ]; then
    puts "Ruby version: `ruby -v`"
  else
    fatal_error "Ruby is not installed. Please install it first."
  fi
  
  is_command_present gem
  if [ $? -eq 0 ]; then
    puts "RubyGems version: `gem -v`"
  else
    fatal_error "RubyGems is not installed. Please install it first."
  fi
  
  puts "Checking Ruby SQLite3 support: $RUBY_SQLITE3_CMD"
  sh -c "$RUBY_SQLITE3_CMD" > /dev/null 2>&1
  [ $? -ne 0 ] && fatal_error "Ruby SQLite3 support not found. Please install it first."

  detect_openvz
  
  if [ "x$FORCE" = "x0" ]; then
    [ -d $INSTALL_DIR ] && fatal_error "Install directory $INSTALL_DIR is not empty. Please remove it before installation."
  fi
  
  puts_spacer
}

detect_openvz()
{
  if [ -f /proc/vz/version ]; then
    ENVIRONMENT="HW-NODE"
    puts "OpenVZ hardware node detected."
  elif [ -d /proc/vz ]; then
    ENVIRONMENT="VPS"
    puts "OpenVZ virtual environment detected."
  else
    ENVIRONMENT="STANDALONE"
    puts "Standalone environment detected."
  fi
}

install_product()
{
  puts "Installation..."
  
  mkdir -p $INSTALL_DIR
  
  exec_cmd "Downloading:" "wget -nc -P $INSTALL_DIR $DOWNLOAD_URL"
  [ $? -ne 0 ] && fatal_error "Failed to download distribution."
  
  ARCHIVE_NAME=`echo $DOWNLOAD_URL | sed 's/.\+\///g'`
  exec_cmd "Unpacking:" "tar --strip 2 -C $INSTALL_DIR -xzf $INSTALL_DIR/$ARCHIVE_NAME"
  
  if [ "x$PRESERVE_ARCHIVE" != "x1" ]; then
    exec_cmd "Removing downloaded archive:" "rm -f $INSTALL_DIR/$ARCHIVE_NAME"
  fi
  
  puts "Installation finished."
  puts "Product was installed into: $INSTALL_DIR"  
  puts_spacer
}

start_services()
{
  puts "Starting services..."
  
  ruby $INSTALL_DIR/script/server -e production -d
  if [ $? -eq 0 ]; then
    puts "Panel was started."
  else
    puts "Unable to start the panel. Please check the logs and try to start it manually."
  fi
    
  if [ "$ENVIRONMENT" = "HW-NODE" ]; then
    HW_DAEMON_CONFIG="$INSTALL_DIR/utils/hw-daemon/hw-daemon.ini"
    if [ ! -f $HW_DAEMON_CONFIG ]; then
      echo "address = 127.0.0.1" >> $HW_DAEMON_CONFIG
      echo "port = 7767" >> $HW_DAEMON_CONFIG
      RAND_KEY=`head -c 200 /dev/urandom | md5sum | awk '{ print \$1 }'`
      echo "key = $RAND_KEY" >> $HW_DAEMON_CONFIG
    fi
    ruby $INSTALL_DIR/utils/hw-daemon/hw-daemon.rb start
    if [ $? -eq 0 ]; then
      puts "Hardware daemon was started."
    else
      puts "Unable to start hardware daemon. Please check the logs and try to start it manually."
    fi
    puts "Adding localhost to the list of controlled servers..."
    ruby $INSTALL_DIR/script/runner -e production "HardwareServer.new(:host => 'localhost', :auth_key => '$RAND_KEY').connect"
    [ $? -ne 0 ] && puts "Failed to add local server."
  else
    puts "Place hardware daemon on machine with OpenVZ."
    puts "To start hardware daemon run:"
    puts "sudo ruby $INSTALL_DIR/utils/hw-daemon/hw-daemon.rb start"
  fi
}

print_how_to_start_services()
{  
  puts_spacer
  
  puts "To start the panel run:"
  puts "sudo ruby $INSTALL_DIR/script/server -e production -d"  
  
  puts "To start hardware daemon run:"
  puts "sudo ruby $INSTALL_DIR/utils/hw-daemon/hw-daemon.rb start"
  
  puts_spacer
}

print_access_info()
{
  puts "Panel should be available at:"
  puts "http://`hostname`:3000"
  puts "Default credentials: admin/admin"
}

main()
{
  puts_separator
  puts "OpenVZ Web Panel $VERSION Installer."
  puts_separator
  
  check_environment
  install_product
  [ "x$AUTOSTART" = "x1" ] && start_services ; true || print_how_to_start_services
  print_access_info  
  puts_separator
}

main