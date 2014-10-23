require 'spec_helper'
require 'restoready_theme'

describe RestoreadyTheme::Cli do
  class CliDouble < RestoreadyTheme::Cli
    attr_writer :local_files, :mock_config

    desc "",""
    def config
      @mock_config || super
    end

    desc "",""
    def restoready_theme_url
      super
    end

    desc "",""
    def binary_file?(file)
      super
    end

    desc "", ""
    def local_files
      @local_files
    end

    desc "",""
    def local_assets_list
      super
    end
  end

  before do
    @cli = CliDouble.new
    @http_client = RestoreadyTheme::HttpClient.new("http://example.com")
    allow(@cli).to receive(:http_client).and_return(@http_client)
  end

  it "should remove assets that are not a part of the white list" do
    @cli.local_files = ['assets/image.png', 'config.yml', 'layouts/theme.liquid', 'locales/en/app.po']
    local_assets_list = @cli.local_assets_list
    expect(local_assets_list.length).to eq 3
    expect(local_assets_list.include?('config.yml')).to be false
  end

  it "should remove assets that are part of the ignore list" do
    @http_client.config = {ignore_files: ['config/settings.html']}
    @cli.local_files = ['assets/image.png', 'layouts/theme.liquid', 'config/settings.html']
    local_assets_list = @cli.local_assets_list

    expect(local_assets_list.length).to eq 2
    expect(local_assets_list.include?('config/settings.html')).to be false
  end

  it "should generate the restoready path URL to the query parameter preview_theme_id if the id is present" do
    @cli.mock_config = {restoready: 'somethingfancy.com', theme_id: 12345}
    expect(@cli.restoready_theme_url).to eq "somethingfancy.com?preview_theme_id=12345"
  end

  it "should generate the restoready path URL withouth the preview_theme_id if the id is not present" do
    @cli.mock_config = {restoready: 'somethingfancy.com'}
    expect(@cli.restoready_theme_url).to eq "somethingfancy.com"

    @cli.mock_config = {restoready: 'somethingfancy.com', theme_id: ''}
    expect(@cli.restoready_theme_url).to eq "somethingfancy.com"
  end

  it "should report binary files as such" do
    extensions = %w(png gif jpg jpeg eot ttf woff otf swf ico pdf)
    extensions.each do |ext|
      expect(@cli.binary_file?("hello.#{ext}")).to be true
    end
  end

  it "should report unknown files as binary files" do
    expect(@cli.binary_file?('omg.wut')).to be true
  end

  it "should not report text based files as binary" do
    expect(@cli.binary_file?('theme.liquid')).to be false
    expect(@cli.binary_file?('style.scss.liquid')).to be false
    expect(@cli.binary_file?('style.css')).to be false
    expect(@cli.binary_file?('application.js')).to be false
    expect(@cli.binary_file?('settings_data.json')).to be false
    expect(@cli.binary_file?('image.jpg')).to be true
    expect(@cli.binary_file?('font.eot')).to be true
    expect(@cli.binary_file?('font.svg')).to be false
  end
end
