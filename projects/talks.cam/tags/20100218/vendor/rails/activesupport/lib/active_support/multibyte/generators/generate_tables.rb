#!/usr/bin/env ruby
begin
  require File.dirname(__FILE__) + '/../../../active_support'
rescue IOError
end
require 'open-uri'
require 'tmpdir'

module ActiveSupport::Multibyte::Handlers #:nodoc:
  class UnicodeDatabase #:nodoc:
    def self.load
      [Hash.new(Codepoint.new),[],{},{}]
    end
  end
  
  class UnicodeTableGenerator #:nodoc:
    BASE_URI = "http://www.unicode.org/Public/#{ActiveSupport::Multibyte::UNICODE_VERSION}/ucd/"
    SOURCES = {
      :codepoints => BASE_URI + 'UnicodeData.txt',
      :composition_exclusion => BASE_URI + 'CompositionExclusions.txt',
      :grapheme_break_property => BASE_URI + 'auxiliary/GraphemeBreakProperty.txt',
      :cp1252 => 'http://unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP1252.TXT'
    }
    
    def initialize
      @ucd = UnicodeDatabase.new
      
      default = Codepoint.new
      default.combining_class = 0
      default.uppercase_mapping = 0
      default.lowercase_mapping = 0
      @ucd.codepoints = Hash.new(default)
      
      @ucd.composition_exclusion = []
      @ucd.composition_map = {}
      @ucd.boundary = {}
      @ucd.cp1252 = {}
    end
    
    def parse_codepoints(line)
      codepoint = Codepoint.new
      raise "Could not parse input." unless line =~ /^
        ([0-9A-F]+);        # code
        ([^;]+);            # name
        ([A-Z]+);           # general category
        ([0-9]+);           # canonical combining class
        ([A-Z]+);           # bidi class
        (<([A-Z]*)>)?       # decomposition type
        ((\ ?[0-9A-F]+)*);  # decompomposition mapping
        ([0-9]*);           # decimal digit
        ([0-9]*);           # digit
        ([^;]*);            # numeric
        ([YN]*);            # bidi mirrored
        ([^;]*);            # unicode 1.0 name
        ([^;]*);            # iso comment
        ([0-9A-F]*);        # simple uppercase mapping
        ([0-9A-F]*);        # simple lowercase mapping
        ([0-9A-F]*)$/ix     # simple titlecase mapping
      codepoint.code              = $1.hex
      #codepoint.name              = $2
      #codepoint.category          = $3
      codepoint.combining_class   = Integer($4)
      #codepoint.bidi_class        = $5
      codepoint.decomp_type       = $7
      codepoint.decomp_mapping    = ($8=='') ? nil : $8.split.collect { |element| element.hex }
      #codepoint.bidi_mirrored     = ($13=='Y') ? true : false
      codepoint.uppercase_mapping = ($16=='') ? 0 : $16.hex
      codepoint.lowercase_mapping = ($17=='') ? 0 : $17.hex
      #codepoint.titlecase_mapping = ($18=='') ? nil : $18.hex
      @ucd.codepoints[codepoint.code] = codepoint
    end

    def parse_grapheme_break_property(line)
      if line =~ /^([0-9A-F\.]+)\s*;\s*([\w]+)\s*#/
        type = $2.downcase.intern
        @ucd.boundary[type] ||= []
        if $1.include? '..'
          parts = $1.split '..'
          @ucd.boundary[type] << (parts[0].hex..parts[1].hex)
        else
          @ucd.boundary[type] << $1.hex
        end
      end
    end
    
    def parse_composition_exclusion(line)
      if line =~ /^([0-9A-F]+)/i
        @ucd.composition_exclusion << $1.hex
      end
    end
    
    def parse_cp1252(line)
      if line =~ /^([0-9A-Fx]+)\s([0-9A-Fx]+)/i
        @ucd.cp1252[$1.hex] = $2.hex
      end
    end
    
    def create_composition_map
      @ucd.codepoints.each do |_, cp|
        if !cp.nil? and cp.combining_class == 0 and cp.decomp_type.nil? and !cp.decomp_mapping.nil? and cp.decomp_mapping.length == 2 and @ucd[cp.decomp_mapping[0]].combining_class == 0 and !@ucd.composition_exclusion.include?(cp.code)
          @ucd.composition_map[cp.decomp_mapping[0]] ||= {}
          @ucd.composition_map[cp.decomp_mapping[0]][cp.decomp_mapping[1]] = cp.code
        end
      end
    end

    def normalize_boundary_map
      @ucd.boundary.each do |k,v|
        if [:lf, :cr].include? k
          @ucd.boundary[k] = v[0]
        end
      end
    end
  
    def parse
      SOURCES.each do |type, url|
        filename =  File.join(Dir.tmpdir, "#{url.split('/').last}")
        unless File.exist?(filename)
          $stderr.puts "Downloading #{url.split('/').last}"
          File.open(filename, 'wb') do |target|
            open(url) do |source|
              source.each_line { |line| target.write line }
            end
          end
        end
        File.open(filename) do |file|
          file.each_line { |line| send "parse_#{type}".intern, line }
        end        
      end
      create_composition_map
      normalize_boundary_map
    end
    
    def dump_to(filename)
      File.open(filename, 'wb') do |f|
        f.write Marshal.dump([@ucd.codepoints, @ucd.composition_exclusion, @ucd.composition_map, @ucd.boundary, @ucd.cp1252])
      end
    end
  end
end

if __FILE__ == $0
  filename = ActiveSupport::Multibyte::Handlers::UnicodeDatabase.filename
  generator = ActiveSupport::Multibyte::Handlers::UnicodeTableGenerator.new
  generator.parse
  print "Writing to: #{filename}"
  generator.dump_to filename
  puts " (#{File.size(filename)} bytes)"
end
