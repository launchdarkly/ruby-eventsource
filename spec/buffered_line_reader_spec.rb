require "ld-eventsource/impl/buffered_line_reader"

def make_tests(name, input_line_chunks:, expected_lines:)
  [{
    name: "#{name}: one chunk per line",
    chunks: input_line_chunks,
    expected: expected_lines,
  }].concat(
    (1..4).map do |size|
      # Here we're lumping together all the content into one string and then
      # re-dividing it into chunks of the specified size. So for instance if the
      # original inputs were ["abcd\n", "efg\n"] and size were 2, the resulting
      # chunks would be ["ab", "cd", "\ne", "fg", "\n"]. This helps to find edge
      # case problems related to line terminators falling at the start of a chunk
      # or in the middle, etc.
      {
        name: "#{name}: #{size}-character chunks",
        chunks: input_line_chunks.join().chars.each_slice(size).map { |a| a.join },
        expected: expected_lines,
      }
    end
  )
end

def tests_for_terminator(term, desc)
  [
    make_tests("non-empty lines",
      input_line_chunks: ["first line" + term, "second line" + term, "3rd line" + term],
      expected_lines: ["first line", "second line", "3rd line"]),

    make_tests("empty first line",
      input_line_chunks: [term, "second line" + term, "3rd line" + term],
      expected_lines: ["", "second line", "3rd line"]),

    make_tests("empty middle line",
      input_line_chunks: ["first line" + term, term, "3rd line" + term],
      expected_lines: ["first line", "", "3rd line"]),

    make_tests("series of empty lines",
      input_line_chunks: ["first line" + term, term, term, term, "3rd line" + term],
      expected_lines: ["first line", "", "", "", "3rd line"]),

    make_tests("multi-line chunks",
      input_line_chunks: ["first line" + term + "second line" + term + "third",
       " line" + term + "fourth line" + term],
      expected_lines: ["first line", "second line", "third line", "fourth line"]),
  ].flatten
end

describe SSE::Impl::BufferedLineReader do
  subject { SSE::Impl::BufferedLineReader }

  terminators = {
    "CR": "\r",
    "LF": "\n",
    "CRLF": "\r\n",
  }

  terminators.each do |desc, term|
    describe "#{desc} terminator" do
      tests_for_terminator(term, desc).each do |test|
        it test[:name] do
          lines = subject.lines_from(test[:chunks])
          expect(lines.to_a).to eq(test[:expected])
        end
      end
    end
  end

  it "mixed terminators" do
    chunks = ["first line\nsecond line\r\nthird line\r",
       "\nfourth line\r", "\r\nlast\r\n"]
    expected = ["first line", "second line", "third line",
      "fourth line", "", "last"]
    expect(subject.lines_from(chunks).to_a).to eq(expected)
  end

  it "decodes from UTF-8" do
    text = "abc€豆腐xyz"
    chunks = [(text + "\n").encode("UTF-8").b]
    expected = [text]
    expect(subject.lines_from(chunks).to_a).to eq(expected)
  end

  it "decodes from UTF-8 when multi-byte characters are split across chunks" do
    text = "abc€豆腐xyz"
    raw = (text + "\n").encode("UTF-8").b
    chunks = raw.bytes.to_a.map{ |byte| byte.chr.force_encoding("UTF-8") }
    # Calling force_encoding("UTF-8") here simulates the behavior of the http gem's
    # readpartial method. It actually returns undecoded bytes that might include an
    # incomplete multi-byte character, but the string's decoding could still be
    # declared as UTF-8. So we are making sure that BufferedLineReader correctly
    # handles such a case.
    expected = [text]
    expect(subject.lines_from(chunks).to_a).to eq(expected)
  end
end
