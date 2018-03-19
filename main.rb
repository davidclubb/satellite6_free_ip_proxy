#!/usr/bin/env ruby
require 'sinatra'
require 'json'
require 'rest-client'

$USER     = 'user'
$PASS     = 'pass'
$SSL_PATH = '/etc/foreman'
$SSL_CERT = '/client_cert.pem'
$SSL_KEY  = '/client_key.pem'
$SSL_CA   = '/proxy_ca.pem'
$SAT_HOST = 'satellite.fqdn.local.'

$0 = "Satellite DHCP Proxy API"
configure do
   set :environment, :production
   set :run, true
   set :lock, false
   set :port, 9099
end

def log (severity, message)
  print "#{Time.now} - [#{severity.upcase}] - #{message}\n"
end

def get_subnets
  begin
    rest_call($SAT_HOST, 443, "/api/v2/subnets", false)
  rescue => e
    log('error', e.to_s + "\n" + e.backtrace.join("\n"))
    raise e
  end
end

def rest_call (fqdn, port, service_url, sslpem)
  resourceConfig = Hash.new

  if sslpem
    begin
      resourceConfig = {
        :ssl_client_cert =>  OpenSSL::X509::Certificate.new(File.read( $SSL_PATH + $SSL_CERT )),
        :ssl_client_key  =>  OpenSSL::PKey::RSA.new(File.read( $SSL_PATH + $SSL_KEY )),
        :ssl_ca_file     =>  $SSL_PATH + $SSL_CA,
        :verify_ssl      =>  OpenSSL::SSL::VERIFY_PEER
      }
    rescue => e
      log("error", "RestCall.init : could not load pem files for REST Communication to #{fqdn}")
      raise e
    end
  else
    resourceConfig = {
      :user       => $USER,
      :password   => $PASS,
      :verify_ssl => OpenSSL::SSL::VERIFY_NONE,
      :headers    => {
        :accept   => 'application/json;version=2'
      }
    }
  end

  log("debug", "RestCall.init : url: https://#{fqdn}:#{port}#{service_url}")
  log("debug", "RestCall.init : rescource_config: #{resourceConfig.inspect}")

  servercall = RestClient::Resource.new( "https://#{fqdn}:#{port}#{service_url}", resourceConfig )

  begin
    JSON.parse(servercall.get)
  rescue => e
    if defined?(e.http_body)
      log.error {"RestCall.call : #{e} -- #{e.http_body}"}
      raise "#{e} (#{e.http_body})"
    else
      log('error', "RestCall.call : #{e}")
      raise e
    end
  end
end

get '/unused_ip/subnet/:subnet' do
  subnets    = Hash.new 
  freeIP     = Hash.new
  subnetName = params[:subnet]
  begin
    subnets    = get_subnets
  rescue => e
    log('error', e.to_s + "\n" + e.backtrace.join("\n"))
    halt 500, '/unused_ip/subnet : Failed to get subnets from satellite server'
  end

  matchedSubnet = subnets['results'].select{|subnet| subnet['ipam'] == 'DHCP' and subnet['name'] == subnetName }
  (halt 404, "/unused_ip/subnet : Coult not find specified subnet name: <#{subnetName}> in satellite" ) if matchedSubnet.empty?
  log('info', "/unused_ip/subnet : found subnet for name: <#{subnetName}>")
  
  relatedCapsule = matchedSubnet.first['dhcp']['name']
  dhcpFROM       = matchedSubnet.first['from']
  dhcpTO         = matchedSubnet.first['to']
  dhcpNET        = matchedSubnet.first['network']
  begin
    rest_call(relatedCapsule, 9090, "/dhcp/#{dhcpNET}/unused_ip?from=#{dhcpFROM}&to=#{dhcpTO}", true).to_json
  rescue => e
    log('error', e.to_s + "\n" + e.backtrace.join("\n"))
    halt 500, '/unused_ip/subnet : Failed to get free ip from capsule API'
  end
end

get '/unused_ip/network/:network' do
  subnets = Hash.new
  freeIP  = Hash.new
  network = params[:network]
  begin
    subnets    = get_subnets
  rescue => e
    log('error', e.to_s + "\n" + e.backtrace.join("\n"))
    halt 500, '/unused_ip/network : Failed to get subnets from satellite server'
  end

  matchedSubnet = subnets['results'].select{|subnet| subnet['ipam'] == 'DHCP' and subnet['network'] == network }
  (halt 404, "/unused_ip/network : Coult not find specified network: <#{network}> in satellite" ) if matchedSubnet.empty?
  log('info', "/unused_ip/network : found subnet for name: <#{network}>")

  relatedCapsule = matchedSubnet.first['dhcp']['name']
  dhcpFROM       = matchedSubnet.first['from']
  dhcpTO         = matchedSubnet.first['to']
  dhcpNET        = matchedSubnet.first['network']
  begin
    rest_call(relatedCapsule, 9090, "/dhcp/#{dhcpNET}/unused_ip?from=#{dhcpFROM}&to=#{dhcpTO}", true).to_json
  rescue => e
    log('error', e.to_s + "\n" + e.backtrace.join("\n"))
    halt 500, '/unused_ip/network : Failed to get free ip from capsule API'
  end
  
end
