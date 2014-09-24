require "spec_helper"

describe Ably::Realtime do
  let(:options) { { api_key: 'app.key:secret' } }

  specify 'constructor returns an Ably::Realtime::Client' do
    expect(Ably::Realtime.new(options)).to be_instance_of(Ably::Realtime::Client)
  end

  describe Ably::Realtime::Client do
    describe "initializing the client" do
      it "should disallow an invalid key" do
        expect { Ably::Realtime::Client.new({}) }.to raise_error(ArgumentError, /api_key is missing/)
        expect { Ably::Realtime::Client.new(api_key: 'invalid') }.to raise_error(ArgumentError, /api_key is invalid/)
        expect { Ably::Realtime::Client.new(api_key: 'invalid:asdad') }.to raise_error(ArgumentError, /api_key is invalid/)
        expect { Ably::Realtime::Client.new(api_key: 'appid.keyuid:keysecret') }.to_not raise_error
      end
    end
  end
end