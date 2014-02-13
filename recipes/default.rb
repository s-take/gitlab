#
# Cookbook Name:: gitlab
# Recipe:: default
#
# Copyright 2014, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

#1.Packages/Dependencies

%w{build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl openssh-server redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev logrotate}.each do |pkg|
  package pkg do
    action :install
  end
end

#git installation
%w{libcurl4-openssl-dev libexpat1-dev gettext libz-dev libssl-dev build-essential}.each do |pkg|
  package pkg do
    action :install
  end
end

script "install_git" do
  not_if 'which git'
  interpreter "bash"
  user        "root"
  code <<-EOL
    cd /tmp
    curl --progress https://git-core.googlecode.com/files/git-1.8.5.2.tar.gz | tar xz
    cd git-1.8.5.2/
    make prefix=/usr/local all
    sudo ake prefix=/usr/local install
  EOL
end

#2.Ruby
script "install_ruby" do
  not_if 'which ruby'
  interpreter "bash"
  user        "root"
  code <<-EOL
    mkdir /tmp/ruby && cd /tmp/ruby
    curl --progress ftp://ftp.ruby-lang.org/pub/ruby/2.0/ruby-2.0.0-p353.tar.gz | tar xz
    cd ruby-2.0.0-p353
    ./configure --disable-install-rdoc
    make
    sudo make install
    sudo gem install bundler --no-ri --no-rdoc
  EOL
end

#3.System Users
user 'git' do
  comment  'GitLab'
  home     '/home/git'
  shell    '/bin/false'
  password nil
  supports :manage_home => true
  action   [:create, :manage]
end

#4 GitLab shell

git "#{node['gitlab']['install_dir']}/gitlab-shell" do
  repository "https://gitlab.com/gitlab-org/gitlab-shell.git"
  reference "v1.8.0"
  action :checkout
  user "git"
  group "git"
end

template "config.yml" do
  owner "git"
  path "#{node['gitlab']['install_dir']}/gitlab-shell/config.yml"
end

script "gitlab_initshell" do
  interpreter "bash"
  user        "git"
  code <<-EOL
    cd #{node['gitlab']['install_dir']}/gitlab-shell
    ./bin/install
  EOL
end

#5.Database
include_recipe "database::mysql"

mysql_connection_info = {
  :host     => 'localhost',
  :username => 'root',
  :password => node['mysql']['server_root_password']
}

mysql_database 'gitlabhq_production' do
  connection mysql_connection_info
  encoding 'UTF8'
  collation 'utf8_unicode_ci'
  action :create
end

mysql_database_user 'git' do
  connection mysql_connection_info
  password   'P@ssw0rd'
  database_name 'gitlabhq_production'
  privileges [:SELECT, :'LOCK TABLES', :INSERT, :UPDATE, :DELETE, :CREATE, :DROP, :INDEX, :ALTER]
  action     [:create, :grant]
end

#6.GitLab

git "#{node['gitlab']['install_dir']}/gitlab" do
  repository "https://gitlab.com/gitlab-org/gitlab-ce.git"
  reference "6-5-stable"
  action :checkout
  user "git"
  group "git"
end

template "gitlab.yml" do
  owner "git"
  path "#{node['gitlab']['install_dir']}/gitlab/config/gitlab.yml"
end

script "chown_mod_gitlab" do
  interpreter "bash"
  user        "root"
  code <<-EOL
    cd /home/git/gitlab
    chown -R git log/
    chown -R git tmp/
    chmod -R u+rwX  log/
    chmod -R u+rwX  tmp/
  EOL
end

directory "/home/git/gitlab-satellites" do
  owner 'git'
  group 'git'
  action :create
end

%w{/home/git/gitlab/tmp/pids /home/git/gitlab/tmp/sockets /home/git/gitlab/public/uploads}.each do |dir|
  directory dir do
    owner 'git'
    group 'git'
    mode 0755
    action :create
  end
end

template "unicorn.rb" do
  owner "git"
  path "#{node['gitlab']['install_dir']}/gitlab/config/unicorn.rb"
end

template "rack_attack.rb" do
  owner "git"
  path "#{node['gitlab']['install_dir']}/gitlab/config/initializers/rack_attack.rb"
end

script "git_global_settings" do
  interpreter "bash"
  user        "git"
  environment "HOME" => "/home/git"
  code <<-EOL
    git config --global user.name "GitLab"
    git config --global user.email "gitlab@localhost"
    git config --global core.autocrlf input
  EOL
end

template "database.yml" do
  owner "git"
  path "#{node['gitlab']['install_dir']}/gitlab/config/database.yml"
end

=begin
script "bundle_install_exec" do
  interpreter "bash"
  user        "git"
  code <<-EOL
    cd /home/git/gitlab
    bundle install --deployment --without development test postgres aws
    bundle exec rake gitlab:setup RAILS_ENV=production
  EOL
end

template "gitlab" do
  owner "root"
  mode 755
  path "/etc/init.d/gitlab"
end

=end

script "make_gitlab_starton" do
  not_if { File.exists?("/etc/logrotate.d/gitlab")}
  interpreter "bash"
  user        "root"
  code <<-EOL
    cd /home/git/gitlab
    lib/support/logrotate/gitlab /etc/logrotate.d/gitlab
    update-rc.d gitlab defaults 21
    service gitlab start
  EOL
end

script "compile_assets" do
  interpreter "bash"
  user        "git"
  code <<-EOL
    cd /home/git/gitlab
    bundle exec rake assets:precompile RAILS_ENV=production
  EOL
end
