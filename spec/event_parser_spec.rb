require "ld-eventsource/impl/event_parser"

describe SSE::Impl::EventParser do
  subject { SSE::Impl::EventParser }

  it "parses an event with all fields" do
    lines = [
      "event: abc\r\n",
      "data: def\r\n",
      "id: 1\r\n",
      "\r\n"
    ]
    ep = subject.new(lines)
    
    expected_event = SSE::StreamEvent.new(:abc, "def", "1")
    output = ep.items.to_a
    expect(output).to eq([ expected_event ])
  end

  it "parses an event with only data" do
    lines = [
      "data: def\r\n",
      "\r\n"
    ]
    ep = subject.new(lines)
    
    expected_event = SSE::StreamEvent.new(:message, "def", nil)
    output = ep.items.to_a
    expect(output).to eq([ expected_event ])
  end

  it "parses an event with multi-line data" do
    lines = [
      "data: def\r\n",
      "data: ghi\r\n",
      "\r\n"
    ]
    ep = subject.new(lines)
    
    expected_event = SSE::StreamEvent.new(:message, "def\nghi", nil)
    output = ep.items.to_a
    expect(output).to eq([ expected_event ])
  end

  it "ignores comments" do
    lines = [
      ":",
      "data: def\r\n",
      ":",
      "\r\n"
    ]
    ep = subject.new(lines)
    
    expected_event = SSE::StreamEvent.new(:message, "def", nil)
    output = ep.items.to_a
    expect(output).to eq([ expected_event ])
  end

  it "parses reconnect interval" do
    lines = [
      "retry: 2500\r\n",
      "\r\n"
    ]
    ep = subject.new(lines)

    expected_item = SSE::Impl::SetRetryInterval.new(2500)
    output = ep.items.to_a
    expect(output).to eq([ expected_item ])
  end

  it "parses multiple events" do
    lines = [
      "event: abc\r\n",
      "data: def\r\n",
      "id: 1\r\n",
      "\r\n",
      "data: ghi\r\n",
      "\r\n"
    ]
    ep = subject.new(lines)
    
    expected_event_1 = SSE::StreamEvent.new(:abc, "def", "1")
    expected_event_2 = SSE::StreamEvent.new(:message, "ghi", nil)
    output = ep.items.to_a
    expect(output).to eq([ expected_event_1, expected_event_2 ])
  end

  it "ignores events with no data" do
    lines = [
      "event: nothing\r\n",
      "\r\n",
      "event: nada\r\n",
      "\r\n"
    ]
    ep = subject.new(lines)
    
    output = ep.items.to_a
    expect(output).to eq([])
  end
end
