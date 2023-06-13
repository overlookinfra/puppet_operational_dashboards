require 'spec_helper'

describe 'puppet_operational_dashboards::profile::dashboards' do
  let(:facts) { { os: { family: 'RedHat' } } }
  let(:pre_condition) do
    <<-PRE_COND
      class{ 'puppet_operational_dashboards':
        include_pe_metrics => true,
        manage_system_board => true,
      }
    PRE_COND
  end

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile }

      case os_facts[:osfamily]
      when 'RedHat', 'Debian'
        it { is_expected.to contain_class('grafana').with(install_method: 'repo') }
      else
        it {
          is_expected.to contain_class('grafana').with(install_method: 'package')
        }
      end
    end
  end

  context 'when using default parameters' do
    it {
      is_expected.to contain_class('grafana').with(
        version: '8.5.20',
        manage_package_repo: true,
      )

      is_expected.to contain_service('grafana').with_ensure('running')

      # I could not get matching to work on a file with a sensitive value.  Maybe we can revisit this later
      # We should check that the url is correct based on $use_ssl and that the token is present
      is_expected.to contain_file('/etc/grafana/provisioning/datasources/influxdb.yaml').that_requires('Class[grafana::install]')
      is_expected.to contain_file('/etc/grafana/provisioning/datasources/influxdb.yaml').that_notifies('Service[grafana-server]')

      ['Filesync Performance', 'Postgresql Performance', 'Puppetdb Performance', 'Puppetserver Performance', 'Orchestrator Performance'].each do |dashboard|
        is_expected.to contain_grafana_dashboard(dashboard).that_requires('Class[grafana::install]')
      end

      is_expected.to contain_file('grafana-conf-d')
      is_expected.to contain_file('wait-for-grafana').with_content(
        %r{ExecStartPost=/usr/bin/timeout 10 sh -c 'while ! ss -t -l -n sport = :3000 | sed 1d | grep -q "^LISTEN.*:3000"; do sleep 1; done'},
      )
      is_expected.to contain_file('wait-for-grafana').that_subscribes_to('Exec[puppet_grafana_daemon_reload]')

      is_expected.to contain_exec('puppet_grafana_daemon_reload').that_notifies('Service[grafana-server]')
    }
  end

  # Because puppet_operational_dashboards includes this class and defining params with a let() changes the class declaration,
  # we have to remove it and specify its parameters to avoid a duplicate resource error
  context 'when not managing grafana' do
    let(:pre_condition) { '' }
    let(:params) do
      {
        token: RSpec::Puppet::Sensitive.new(nil),
        use_ssl: true,
        influxdb_host: 'localhost',
        influxdb_port: 8086,
        influxdb_bucket: 'puppet_data',
        telegraf_token_name: 'puppet telegraf token',
        influxdb_token_file: '/root/.influxdb_token',
        manage_grafana: false,
        grafana_use_ssl: false,
        grafana_ssl_cert_file: '/etc/grafana/client.pem',
        grafana_ssl_key_file: '/etc/grafana/client.key',
        include_pe_metrics: true,
        manage_system_board: true,
      }
    end

    it {
      is_expected.not_to contain_class('grafana')
      is_expected.not_to contain_file('wait-for-grafana')
      is_expected.not_to contain_file('grafana-conf-d')

      # We expect the dashboards to be managed, but to not require the install class
      ['Filesync Performance', 'Postgresql Performance', 'Puppetdb Performance', 'Puppetserver Performance', 'Orchestrator Performance'].each do |dashboard|
        is_expected.to contain_grafana_dashboard(dashboard)
        is_expected.not_to contain_grafana_dashboard(dashboard).that_requires('Class[grafana::install]')
      end
    }
  end

  context 'when passing a token' do
    let(:pre_condition) { '' }
    let(:params) do
      {
        token: RSpec::Puppet::Sensitive.new('foo'),
        use_ssl: true,
        influxdb_host: 'localhost',
        influxdb_port: 8086,
        influxdb_bucket: 'puppet_data',
        telegraf_token_name: 'puppet telegraf token',
        influxdb_token_file: '/root/.influxdb_token',
        include_pe_metrics: true,
        manage_system_board: true,
        manage_grafana: true,
        grafana_use_ssl: false,
        grafana_ssl_cert_file: '/etc/grafana/client.pem',
        grafana_ssl_key_file: '/etc/grafana/client.key',
      }
    end

    it {
      # I could not get matching to work on a file with a sensitive value.  Maybe we can revisit this later
      # We should check that the url is correct based on $use_ssl and that the token is present
      is_expected.to contain_file('grafana_provisioning_datasource')
      is_expected.to contain_file('grafana_provisioning_datasource').that_requires('Class[grafana::install]')
    }
  end

  context 'when managing system dashboards' do
    it {
      is_expected.to contain_grafana_dashboard('System_v2 Performance').with_ensure('present')
    }
  end

  context 'when not managing system dashboards' do
    let(:pre_condition) { '' }
    let(:params) do
      {
        token: RSpec::Puppet::Sensitive.new('foo'),
        use_ssl: true,
        influxdb_host: 'localhost',
        influxdb_port: 8086,
        influxdb_bucket: 'puppet_data',
        telegraf_token_name: 'puppet telegraf token',
        influxdb_token_file: '/root/.influxdb_token',
        include_pe_metrics: true,
        manage_system_board: false,
        manage_grafana: true,
        grafana_use_ssl: false,
        grafana_ssl_cert_file: '/etc/grafana/client.pem',
        grafana_ssl_key_file: '/etc/grafana/client.key',
      }
    end

    it {
      is_expected.to contain_grafana_dashboard('System_v2 Performance').with_ensure('absent')
      is_expected.to contain_grafana_dashboard('System Performance').with_ensure('absent')
    }
  end
end
