module SSE
  module Impl
    class BufferedLineReader
      #
      # Reads a series of data chunks from an enumerator, and returns an enumerator that
      # parses/aggregates these into text lines. The line terminator may be CR, LF, or
      # CRLF for each line; terminators are not included in the returned lines. When the
      # input data runs out, the output enumerator ends and does not include any partially
      # completed line.
      #
      # @param [Enumerator] chunks  an enumerator that will yield strings from a stream -
      #  these are treated as raw UTF-8 bytes, regardless of the string's declared encoding
      #  (so it is OK if a multi-byte character is split across chunks); if the declared
      #  encoding of the chunk is not ASCII-8BIT, it will be changed to ASCII-8BIT in place
      # @return [Enumerator]  an enumerator that will yield one line at a time in UTF-8
      #
      def self.lines_from(chunks)
        buffer = +"".b
        position = 0
        line_start = 0
        last_char_was_cr = false

        Enumerator.new do |gen|
          chunks.each do |chunk|
            chunk = chunk.dup.force_encoding("ASCII-8BIT")
            buffer += chunk

            loop do
              # Search for a line break in any part of the buffer that we haven't yet seen.
              i = buffer.index(/[\r\n]/, position)
              if i.nil?
                # There isn't a line break yet, so we'll keep accumulating data in the buffer, using
                # position to keep track of where we left off scanning. We can also discard any previously
                # parsed lines from the buffer at this point.
                if line_start > 0
                  buffer.slice!(0, line_start)
                  line_start = 0
                end
                position = buffer.length
                break
              end

              ch = buffer[i]
              if i == 0 && ch == "\n" && last_char_was_cr
                # This is just the dangling LF of a CRLF pair
                last_char_was_cr = false
                i += 1
                position = i
                line_start = i
                next
              end

              line = buffer[line_start, i - line_start].force_encoding("UTF-8")
              # Calling force_encoding just declares that we believe the encoding of this string to be
              # UTF-8 (which is the only encoding allowed in the SSE protocol); it doesn't cause any
              # re-decoding of the string. The previous line-parsing steps were done on raw 8-bit
              # strings so that it won't try to do any UTF-8 decoding on intermediate slices.

              last_char_was_cr = false
              i += 1
              if ch == "\r"
                if i == buffer.length
                  last_char_was_cr = true # We'll break the line here, but be on watch for a dangling LF
                elsif buffer[i] == "\n"
                  i += 1
                end
              end
              if i == buffer.length
                buffer = ""
                i = 0
              end
              position = i
              line_start = i
              gen.yield line
            end
          end
        end
      end
    end
  end
end
