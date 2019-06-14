module NCMCAuthorities
  module Matching
    class Match
      attr_reader :name, :other_name, :score, :explanation, :category

      def initialize(name1, name2, score = nil)
        @name = name1
        @other_name = name2
        @score = score if score
      end

      def names
        [@name, @other_name]
      end

      def score
        unless @score
          @score, @explanation = self.class.score(name, other_name, name.type)
        end
        @category = self.class.categorize(@score, name.type)
        @score
      end

      def category
        score unless @score
        @category = self.class.categorize(@score, name.type)
      end

      def self.rank(name, other_names)
        other_names.
          uniq.
          reject { |m| m.equal? name }.
          map { |other| Match.new(name, other) }.
          sort_by { |match| [-match.score, match.other_name ] }
      end

      def self.categorize(score, type)
        case type
        when 'personal', 'family'
          case score
          when 0.9..100.0
            :strong
          when 0.8..0.9
            :moderate
          when 0.7..0.8
            :weak
          else
            :bad
          end
        when 'corporate', 'meeting'
          case score
          when 0.75..100.0
            :strong
          when 0.60..0.75
            :moderate
          when 0.55..0.60
            :weak
          else
            :bad
          end
        end
      end

      def self.score(name, other_name, name_type)
        send(:"#{name_type}_score", name, other_name)
      end

      # Corporate names have a score from solr assigned to the match
      def self.corporate_score(name, other_name)
        return
      end

      # Meeting names have a score from solr assigned to the match
      def self.meeting_score(name, other_name)
        corporate_score(name, other_name)
      end


      def self.family_score(name, other_name)
        Matching::StringComparator.compare(name.basename, other_name.basename, :levenshtein)[:levenshtein]
      end

      def self.personal_score(name, other_name)
        surname = Matching::StringComparator.compare(name.surname, other_name.surname, :levenshtein)
        forename = Matching::StringComparator.compare(name.forename, other_name.forename, :levenshtein, :forename_tokens)
        #initials = Matching::StringComparator.compare(name.initials, other_name.initials, :jaro_winkler)
        supplemental = Matching::StringComparator.compare(name.supplemental, other_name.supplemental, :trigram)
        #dates = 0

        factors = [
          ['surname levenshtein', surname[:levenshtein], 1.5, 5],
          ['forename levenshtein', forename[:levenshtein], 1, 1],
          ['forename tokens', forename[:forename_tokens], 1, 4],
          ['supplemental',
           supplemental[:trigram].nan? ? 0.0 : supplemental[:trigram], 1, 1]
        ]

        explanation = {}
        factors.each do |row|
          fname, base_score, severity, weight = row
          score = base_score ** severity * weight
          explanation[fname] = {base_score: base_score, severity: severity,
                              weight: weight, score: score}
        end

        score = (explanation.values.map { |v| v[:score] }.reduce(:+)) / \
          (explanation.values.map { |v| v[:weight] }.reduce(:+))

        [score, explanation]
      end
    end
  end
end
