require 'spec_helper'
require 'yubioath'

RSpec.describe YubiOATH, :aggregate_failures do
  let(:yubikey) { Card.new(name: 'Yubico Yubikey NEO OTP+CCID') }
  def yubioath
    yubikey.tap do |card|
      yield YubiOATH.new(card)
    end
  end

  let(:select) { [0x00, 0xA4, 0x04, 0x00, YubiOATH::AID.length, *YubiOATH::AID].map(&:chr).join }
  let(:list) { [0x00, 0xA1, 0x00, 0x00].map(&:chr).join }
  let(:reset) { [0x00, 0x04, 0xDE, 0xAD].map(&:chr).join }
  let(:success) { [0x90, 0x00].map(&:chr) }

  before do
    yubikey.tap do |card|
      card.transmit(select)
      @skip = false
      if (card.transmit(list).chars - success).any?
        @skip = true
        raise 'card not empty'
      end
    end
  end

  it 'lists OTP tokens and their configurations' do
    yubioath do |applet|
      expect(applet.list).to eq({})

      expect(applet.put(name: 'foo', secret: nil)).to eq(true)
      expect(applet.put(name: 'bar', secret: nil)).to eq(true)

      expect(applet.list).to eq({
        'foo' => {type: :TOTP, algorithm: :SHA256},
        'bar' => {type: :TOTP, algorithm: :SHA256},
      })
    end
  end

  let(:t1) { Time.parse('2013-01-01T00:00:00Z') }
  let(:t2) { Time.parse('2014-06-15T12:00:00Z') }
  let(:t3) { Time.parse('2015-12-31T23:59:59Z') }

  it 'calculates OTP tokens' do
    yubioath do |applet|
      {'foo' => '123', 'bar' => '456', 'qux' => '789'}.each do |name, secret|
        applet.put(name: name, secret: secret)
      end

      expect(applet.calculate(name: 'foo', timestamp: t1)).to eq '947217'
      expect(applet.calculate(name: 'bar', timestamp: t1)).to eq '576740'
      expect(applet.calculate(name: 'qux', timestamp: t1)).to eq '129094'

      expect(applet.calculate(name: 'foo', timestamp: t2)).to eq '904502'
      expect(applet.calculate(name: 'bar', timestamp: t2)).to eq '958008'
      expect(applet.calculate(name: 'qux', timestamp: t2)).to eq '552048'

      expect(applet.calculate(name: 'foo', timestamp: t3)).to eq '204573'
      expect(applet.calculate(name: 'bar', timestamp: t3)).to eq '329294'
      expect(applet.calculate(name: 'qux', timestamp: t3)).to eq '169757'
    end
  end

  it 'calculates all OTP tokens' do
    yubioath do |applet|
      { 'foo' => '123', 'bar' => '456', 'qux' => '789' }.each do |name, secret|
        applet.put(name: name, secret: secret)
      end

      expect(applet.calculate_all(timestamp: t1)).to eq({
        'foo' => '947217',
        'bar' => '576740',
        'qux' => '129094',
      })

      expect(applet.calculate_all(timestamp: t2)).to eq({
        'foo' => '904502',
        'bar' => '958008',
        'qux' => '552048',
      })

      expect(applet.calculate_all(timestamp: t3)).to eq({
        'foo' => '204573',
        'bar' => '329294',
        'qux' => '169757',
      })
    end
  end

  it 'deletes OTP tokens' do
    yubioath do |applet|
      applet.put(name: 'foo', secret: nil)
      applet.put(name: 'bar', secret: nil)

      expect(applet.list.keys).to match_array(['foo', 'bar'])

      expect(applet.delete(name: 'foo')).to eq(true)
      expect(applet.delete(name: 'bar')).to eq(true)

      expect(applet.list.keys).to eq([])
    end
  end

  it 'resets the applet' do
    yubioath do |applet|
      applet.put(name: 'foo', secret: nil)
      applet.put(name: 'bar', secret: nil)

      expect(applet.list.keys).to match_array(['foo', 'bar'])

      expect(applet.reset).to eq(true)

      expect(applet.list.keys).to eq([])
    end
  end

  after do
    yubikey.tap do |card|
      break if @skip
      card.transmit(select)
      raise 'unable to reset after test suite' unless card.transmit(reset).chars == success
    end
  end
end
