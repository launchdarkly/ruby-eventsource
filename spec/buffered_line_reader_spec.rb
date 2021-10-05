require "ld-eventsource/impl/buffered_line_reader"

def tests_for_terminator(term, desc)
  def make_tests(name, input_line_chunks, expected_lines)
    [{
      name: "#{name}: one chunk per line",
      chunks: input_line_chunks,
      expected: expected_lines
    }].concat(
      (1..4).map do |size|
        ({
          name: "#{name}: #{size}-character chunks",
          chunks: input_line_chunks.join().chars.to_a.each_slice(size).map { |a| a.join },
          expected: expected_lines
        })
      end
    )
  end
  [
    make_tests("non-empty lines",
      ["first line" + term, "second line" + term, "3rd line" + term],
      ["first line", "second line", "3rd line"]),

    make_tests("empty first line",
      [term, "second line" + term, "3rd line" + term],
      ["", "second line", "3rd line"]),

    make_tests("empty middle line",
      ["first line" + term, term, "3rd line" + term],
      ["first line", "", "3rd line"]),

    make_tests("series of empty lines",
      ["first line" + term, term, term, term, "3rd line" + term],
      ["first line", "", "", "", "3rd line"]),

    make_tests("multi-line chunks",
      ["first line" + term + "second line" + term + "third",
       " line" + term + "fourth line" + term],
      ["first line", "second line", "third line", "fourth line"])
  ].flatten
end

describe SSE::Impl::BufferedLineReader do
  subject { SSE::Impl::BufferedLineReader }

  terminators = {
    "CR": "\r",
    "LF": "\n",
    "CRLF": "\r\n"
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
end
