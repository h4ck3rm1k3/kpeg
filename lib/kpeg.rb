require 'strscan'

module KPeg
  class Parser < StringScanner
    def initialize(str)
      super str
      # A 2 level hash.
      @memoizations = Hash.new { |h,k| h[k] = {} }
    end

    attr_reader :memoizations

    class MemoEntry
      def initialize(ans, pos)
        @ans = ans
        @pos = pos
        @uses = 1
      end

      attr_reader :ans, :pos, :uses

      def inc!
        @uses += 1
      end
    end

    def apply(rule)
      if m = @memoizations[rule][pos]
        m.inc!
        self.pos = m.pos
        return m.ans
      else
        # Save the current position to use below
        start_pos = pos
        ans = rule.match(self)

        # Be sure the MemoEntry has the post eval position
        # so we reset it properly later
        m = MemoEntry.new(ans, pos)
        @memoizations[rule][start_pos] = m
        return ans
      end
    end
  end

  class Match
    def initialize(node, arg)
      @node = node
      if arg.kind_of? String
        @string = arg
      else
        @matches = arg
      end
    end

    attr_reader :node, :string, :matches
  end

  class LiteralString
    def initialize(str)
      @str = Regexp.new Regexp.quote(str)
    end

    def match(x)
      if str = x.scan(@str)
        Match.new(self, str)
      end
    end
  end

  class Choice
    def initialize(*many)
      @choices = many
    end

    def match(x)
      @choices.each do |c|
        pos = x.pos

        if m = x.apply(c)
          return m
        end

        x.pos = pos
      end

      return nil
    end
  end

  class Multiple
    def initialize(node, min, max)
      @node = node
      @min = min
      @max = max
    end

    def match(x)
      n = 0
      matches = []

      while true
        if m = x.apply(@node)
          matches << m
        else
          break
        end

        n += 1

        return nil if @max and n > @max
      end

      if n >= @min
        return Match.new(self, matches)
      end
    end
  end

  class Sequence
    def initialize(*nodes)
      @nodes = nodes
    end

    def match(x)
      matches = @nodes.map do |n|
        if m = x.apply(n)
          m
        else
          return nil
        end
      end

      Match.new(self, matches)
    end
  end

  class AndPredicate
    def initialize(node)
      @node = node
    end

    def match(x)
      pos = x.pos
      matched = x.apply(@node)
      x.pos = pos
      return matched ? Match.new(self, "") : nil
    end
  end

  class NotPredicate
    def initialize(node)
      @node = node
    end

    def match(x)
      pos = x.pos
      matched = x.apply(@node)
      x.pos = pos

      return matched ? nil : Match.new(self, "")
    end
  end

  class RuleReference
    def initialize(layout, name)
      @layout = layout
      @name = name
    end

    def match(x)
      rule = @layout.find(@name)
      raise "Unknown rule: '#{@name}'" unless rule
      x.apply(rule)
    end
  end

  class Layout
    def initialize
      @rules = {}
    end

    def set(name, rule)
      if @rules.key? name
        raise "Already set rule named '#{name}'"
      end

      @rules[name] = rule
    end

    def find(name)
      @rules[name]
    end

    def method_missing(meth, *args)
      meth = meth.to_s

      if meth[-1,1] == "="
        rule = args.first
        set(meth[0..-2], rule)
        return rule
      elsif rule = @rules[meth]
        return rule
      end

      super
    end

    def str(str)
      LiteralString.new(str)
    end

    def any(*nodes)
      Choice.new(*nodes)
    end

    def multiple(node, min, max)
      Multiple.new(node, min, max)
    end

    def maybe(node)
      multiple(node, 0, 1)
    end

    def many(node)
      multiple(node, 1, nil)
    end

    def kleene(node)
      multiple(node, 0, nil)
    end

    def seq(*nodes)
      Sequence.new(*nodes)
    end

    def andp(node)
      AndPredicate.new(node)
    end

    def notp(node)
      NotPredicate.new(node)
    end

    def ref(name)
      RuleReference.new(self, name.to_s)
    end
  end

  def self.layout
    l = Layout.new
    yield l
  end

  def self.match(str, node)
    scan = Parser.new(str)
    scan.apply(node)
  end
end