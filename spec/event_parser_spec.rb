require "ld-eventsource/impl/event_parser"

describe SSE::Impl::EventParser do
  subject { SSE::Impl::EventParser }

  def verify_parsed_events(lines:, expected_events:)
    ep = subject.new(lines)
    output = ep.items.to_a
    expect(output).to eq(expected_events)
  end

  it "parses an event with all fields" do
    lines = [
      "event: abc",
      "data: def",
      "id: 1",
      ""
    ]
    ep = subject.new(lines)
    
    expected_event = SSE::StreamEvent.new(:abc, "def", "1")
    output = ep.items.to_a
    expect(output).to eq([ expected_event ])
  end

  it "parses an event with only data" do
    lines = [
      "data: def",
      ""
    ]
    ep = subject.new(lines)
    
    expected_event = SSE::StreamEvent.new(:message, "def", nil)
    output = ep.items.to_a
    expect(output).to eq([ expected_event ])
  end

  it "parses an event with multi-line data" do
    lines = [
      "data: def",
      "data: ghi",
      ""
    ]
    ep = subject.new(lines)
    
    expected_event = SSE::StreamEvent.new(:message, "def\nghi", nil)
    output = ep.items.to_a
    expect(output).to eq([ expected_event ])
  end

  it "parses an event with empty data" do
    verify_parsed_events(
      lines: [
        "data:",
        ""
      ],
      expected_events: [
        SSE::StreamEvent.new(:message, "", nil)
      ])
  end

  it "ignores comments" do
    lines = [
      ":",
      "data: def",
      ":",
      ""
    ]
    ep = subject.new(lines)
    
    expected_event = SSE::StreamEvent.new(:message, "def", nil)
    output = ep.items.to_a
    expect(output).to eq([ expected_event ])
  end

  it "parses reconnect interval" do
    lines = [
      "retry: 2500",
      ""
    ]
    ep = subject.new(lines)

    expected_item = SSE::Impl::SetRetryInterval.new(2500)
    output = ep.items.to_a
    expect(output).to eq([ expected_item ])
  end

  it "parses multiple events" do
    lines = [
      "event: abc",
      "data: def",
      "id: 1",
      "",
      "data: ghi",
      ""
    ]
    ep = subject.new(lines)
    
    expected_event_1 = SSE::StreamEvent.new(:abc, "def", "1")
    expected_event_2 = SSE::StreamEvent.new(:message, "ghi", nil)
    output = ep.items.to_a
    expect(output).to eq([ expected_event_1, expected_event_2 ])
  end

  it "ignores events with no data" do
    lines = [
      "event: nothing",
      "",
      "event: nada",
      ""
    ]
    ep = subject.new(lines)
    
    output = ep.items.to_a
    expect(output).to eq([])
  end
end
