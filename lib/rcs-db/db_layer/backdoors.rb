#
# Mix-in for DB Layer
#

module Backdoors

  def backdoor_evidence_key(bid)
    key = mysql_query("SELECT logkey FROM backdoor WHERE backdoor_id = #{bid}").to_a
    return key[0][:logkey]
  end

  def backdoor_class_keys
    mysql_query("SELECT build, confkey FROM backdoor WHERE class = 1").to_a
  end

  def backdoor_class_key(build)
    mysql_query("SELECT build, confkey FROM backdoor WHERE class = 1 AND build = '#{build}'").to_a
  end

  def backdoor_status(build, instance, subtype)
    mysql_query("SELECT backdoor_id, status, deleted
                 FROM backdoor
                 WHERE build = '#{build}ss'
                       AND instance = '#{instance}'
                       AND subtype = '#{subtype}'").to_a.first
  end

end