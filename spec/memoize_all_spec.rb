# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize do
  describe ".memoize_all" do
    let(:test_class) do
      Class.new do
        prepend SafeMemoize

        def foo
          rand
        end

        def bar(x)
          rand + x
        end

        def baz
          rand
        end

        private

        def secret
          rand
        end

        memoize_all
      end
    end

    it "memoizes all public methods" do
      instance = test_class.new
      expect(instance.foo).to eq(instance.foo)
      expect(instance.bar(1)).to eq(instance.bar(1))
      expect(instance.baz).to eq(instance.baz)
    end

    it "caches per unique arguments" do
      instance = test_class.new
      expect(instance.bar(1)).not_to eq(instance.bar(2))
      expect(instance.bar(1)).to eq(instance.bar(1))
    end

    it "does not memoize private methods" do
      instance = test_class.new
      results = Array.new(3) { instance.send(:secret) }
      expect(results.uniq.size).to be > 1
    end

    it "does not share cache between instances" do
      a = test_class.new
      b = test_class.new
      expect(a.foo).not_to eq(b.foo)
    end

    context "with except:" do
      let(:selective_class) do
        Class.new do
          prepend SafeMemoize

          def cheap
            rand
          end

          def expensive
            rand
          end

          memoize_all except: [:cheap]
        end
      end

      it "memoizes methods not in the exclusion list" do
        instance = selective_class.new
        expect(instance.expensive).to eq(instance.expensive)
      end

      it "does not memoize excluded methods" do
        instance = selective_class.new
        results = Array.new(3) { instance.cheap }
        expect(results.uniq.size).to be > 1
      end

      it "accepts string method names in except:" do
        klass = Class.new do
          prepend SafeMemoize

          def foo
            rand
          end

          def bar
            rand
          end

          memoize_all except: ["foo"]
        end

        instance = klass.new
        expect(instance.bar).to eq(instance.bar)
        results = Array.new(3) { instance.foo }
        expect(results.uniq.size).to be > 1
      end
    end

    context "with shared options" do
      it "applies ttl: to all methods" do
        klass = Class.new do
          prepend SafeMemoize

          def value
            rand
          end

          memoize_all ttl: 0.1
        end

        instance = klass.new
        first = instance.value
        expect(instance.value).to eq(first)
        sleep(0.15)
        expect(instance.value).not_to eq(first)
      end

      it "applies max_size: to all methods" do
        klass = Class.new do
          prepend SafeMemoize

          def find(id)
            rand + id
          end

          memoize_all max_size: 2
        end

        instance = klass.new
        instance.find(1)
        instance.find(2)
        instance.find(3)
        expect(instance.memo_count(:find)).to eq(2)
      end

      it "applies if: to all methods" do
        klass = Class.new do
          prepend SafeMemoize

          def compute
            nil
          end

          memoize_all if: ->(result) { !result.nil? }
        end

        instance = klass.new
        3.times { instance.compute }
        expect(instance.memo_count(:compute)).to eq(0)
      end
    end

    context "with include_protected: true" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          def public_method = rand

          protected

          def protected_method = rand

          memoize_all include_protected: true
        end
      end

      it "memoizes protected methods" do
        instance = klass.new
        results = Array.new(3) { instance.send(:protected_method) }
        expect(results.uniq.size).to eq(1)
      end

      it "still memoizes public methods" do
        instance = klass.new
        expect(instance.public_method).to eq(instance.public_method)
      end
    end

    context "with include_private: true" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          def public_method = rand

          private

          def private_method = rand

          memoize_all include_private: true
        end
      end

      it "memoizes private methods" do
        instance = klass.new
        results = Array.new(3) { instance.send(:private_method) }
        expect(results.uniq.size).to eq(1)
      end

      it "still memoizes public methods" do
        instance = klass.new
        expect(instance.public_method).to eq(instance.public_method)
      end
    end

    context "isolation" do
      it "does not affect other classes" do
        klass = Class.new do
          prepend SafeMemoize

          def value
            rand
          end
        end

        instance = klass.new
        results = Array.new(3) { instance.value }
        expect(results.uniq.size).to be > 1
      end
    end
  end
end
