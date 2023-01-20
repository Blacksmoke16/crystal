@[Link("pcre")]
lib LibPCRE
  alias Int = LibC::Int

  CASELESS      = 0x00000001
  MULTILINE     = 0x00000002
  DOTALL        = 0x00000004
  EXTENDED      = 0x00000008
  ANCHORED      = 0x00000010
  UTF8          = 0x00000800
  NO_UTF8_CHECK = 0x00002000
  DUPNAMES      = 0x00080000
  UCP           = 0x20000000

  struct Extra
    flags : LibC::ULong
    study_data : Void*
    match_limit : LibC::ULong
    callout_data : Void*
    tables : LibC::UChar*
    match_limit_recursion : LibC::ULong
    mark : LibC::UChar**
    executable_jit : Void*
  end

  type Pcre = Void*

  fun compile = pcre_compile(pattern : UInt8*, options : Int, errptr : UInt8**, erroffset : Int*, tableptr : Void*) : Pcre
  fun config = pcre_config(what : Int, where : Int*) : Int
  fun exec = pcre_exec(code : Pcre, extra : Extra*, subject : UInt8*, length : Int, offset : Int, options : Int, ovector : Int*, ovecsize : Int) : Int
  fun study = pcre_study(code : Pcre, options : Int, errptr : UInt8**) : Extra*
  fun free_study = pcre_free_study(extra : Extra*) : Void
  fun full_info = pcre_fullinfo(code : Pcre, extra : Extra*, what : Int, where : Int*) : Int
  fun get_stringnumber = pcre_get_stringnumber(code : Pcre, string_name : UInt8*) : Int
  fun get_stringtable_entries = pcre_get_stringtable_entries(code : Pcre, name : UInt8*, first : UInt8**, last : UInt8**) : Int

  CONFIG_JIT = 9

  STUDY_JIT_COMPILE = 0x0001

  INFO_CAPTURECOUNT  = 2
  INFO_NAMEENTRYSIZE = 7
  INFO_NAMECOUNT     = 8
  INFO_NAMETABLE     = 9

  EXTRA_MARK = 0x0020

  $free = pcre_free : Void* ->
end
