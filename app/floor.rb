# frozen_string_literal: true

require 'json'

class Floor
  attr_accessor :floor_id, :image, :text, :gold, :gold_diff, :max_hp, :hp, :hp_diff, :player_choise, :obtain_objects,
                :obtain_chosen_cards, :upgrade_cards, :remove_cards, :bottled_cards

  def initialize
    @floor_id            = 0
    @image               = 'no_image'
    @text                = 'no text'
    @gold                = 99
    @gold_diff           = 99
    @max_hp              = -1
    @hp                  = -1
    @player_choise       = nil
    @hp_diff             = 0
    @obtain_objects      = []
    @obtain_chosen_cards = []
    @upgrade_cards       = []
    @remove_cards        = []
    @bottled_cards       = []
  end
end

class RunSummary
  attr_accessor :victory, :floor_reached, :ascension_level, :character_chosen

  def initialize(summary_json)
    summary = JSON.parse(summary_json)
    @victory = summary['victory']
    @floor_reached = summary['floor_reached']
    @ascension_level = summary['ascension_level']
    @character_chosen = summary['character_chosen']
  end
end

class Run
  attr_reader :raw_json
  attr_accessor :victory, :floor_reached, :ascension_level, :character_chosen, :seed_text, :localtime, :master_deck, :relics, :floors, :bosses, :maps

  def initialize(run_json)
    run_data = JSON.parse(run_json)

    raise "seed error" unless run_data['seed_played'].match(/^-?\d+$/)

    @raw_json = run_data
    @victory = run_data['victory']
    @floor_reached = run_data['floor_reached']
    @ascension_level = run_data.fetch('ascension_level', 0)
    @character_chosen = run_data['character_chosen']
    @seed_text = convert_raw_seed_to_string(run_data['seed_played'].to_i)
    @localtime = run_data['local_time'].gsub(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2}).*$/, '\1-\2-\3 \4:\5')
    @master_deck = run_data['master_deck']
    @relics = run_data['relics']
    @bosses = [nil,nil,nil]
    @maps = generate_map(run_data['seed_played'], run_data['path_taken'], run_data['relics'].include?('WingedGreaves'), @ascension_level == 0)

    @floors = []
    @floors << Floor.new
    if !run_data['neow_bonus'].nil? && run_data['neow_cost']
      @floors[0].image = 'neow'
      @floors[0].player_choise = "#{run_data['neow_bonus']}/#{run_data['neow_cost']}"
    end

    run_data['path_per_floor'].each_with_index do |t, idx|
      f = Floor.new
      case t
      when 'T'
        f.image = 'chest'
      when '$'
        f.image = 'shop'
      when nil
        f.image = "#{@character_chosen}_win"
      end
      f.text = t
      f.floor_id = idx + 1
      @floors << f
    end

    # TODO: 心臓にトライしない場合は別の画像を使う
    if (@ascension_level < 20) && (@floors.size >= 52)
      @floors[51].image = 'door'
    elsif (@ascension_level >= 20) && (@floors.size >= 53)
      @floors[52].image = 'door'
    end

    run_data['card_choices'].each do |e|
      @floors[e['floor'].to_i].obtain_chosen_cards << e
    end

    unless run_data['boss_relics'].nil?
      # TODO: フロア数のハードコードをやめる(path_per_floorの値を活用する)
      if run_data['boss_relics'].size >= 1
        @floors[17].image = 'boss_chest'
        @floors[17].obtain_chosen_cards << run_data['boss_relics'][0]
      end
      if run_data['boss_relics'].size >= 2
        @floors[34].image = 'boss_chest'
        @floors[34].obtain_chosen_cards << run_data['boss_relics'][1]
      end
    end

    run_data['damage_taken'].each do |e|
      @floors[e['floor'].to_i].image = e['enemies']
    end
    @bosses[0] = run_data['damage_taken'].find(proc{{}}){|e|e['floor'].to_i == 16}['enemies']
    @bosses[1] = run_data['damage_taken'].find(proc{{}}){|e|e['floor'].to_i == 33}['enemies']
    @bosses[2] = run_data['damage_taken'].find(proc{{}}){|e|e['floor'].to_i == 50}['enemies']

    run_data['event_choices'].each do |e|
      @floors[e['floor'].to_i].image =
        if ['Golden Idol', 'Mysterious Sphere'].include? e['event_name']
          "#{e['event_name']} Event"
        else
          e['event_name']
        end
      @floors[e['floor'].to_i].player_choise = e['player_choice']
      @floors[e['floor'].to_i].remove_cards += e['cards_removed'] unless e['cards_removed'].nil?
      @floors[e['floor'].to_i].remove_cards += e['cards_transformed'] unless e['cards_transformed'].nil?
      @floors[e['floor'].to_i].obtain_objects += e['cards_obtained'] unless e['cards_obtained'].nil?
      @floors[e['floor'].to_i].upgrade_cards += e['cards_upgraded'] unless e['cards_upgraded'].nil?
      @floors[e['floor'].to_i].obtain_objects += e['relics_obtained'] unless e['relics_obtained'].nil?
    end

    run_data['campfire_choices'].each do |e|
      @floors[e['floor'].to_i].image = 'campfire'
      @floors[e['floor'].to_i].player_choise = e['key']
      @floors[e['floor'].to_i].upgrade_cards << e['data'] if e['key'] == 'SMITH'
      @floors[e['floor'].to_i].remove_cards << e['data'] if e['key'] == 'PURGE'
    end

    run_data['relics_obtained'].each do |e|
      @floors[e['floor'].to_i].obtain_objects << e['key']
    end

    pre_gold = 99
    run_data['gold_per_floor'].each_with_index do |e, idx|
      @floors[idx + 1].gold = e
      @floors[idx + 1].gold_diff = e - pre_gold
      pre_gold = e
    end

    pre_hp = @floors[0].hp = run_data['current_hp_per_floor'][0]
    run_data['current_hp_per_floor'].each_with_index do |e, idx|
      @floors[idx + 1].hp = e
      @floors[idx + 1].hp_diff = e - pre_hp
      pre_hp = e
    end

    @floors[0].max_hp = run_data['max_hp_per_floor'][0]
    run_data['max_hp_per_floor'].each_with_index do |e, idx|
      @floors[idx + 1].max_hp = e
    end

    run_data['item_purchase_floors'].each_with_index do |e, idx|
      @floors[e.to_i].obtain_objects << run_data['items_purchased'][idx]
    end

    run_data['items_purged_floors'].each_with_index do |e, idx|
      @floors[e.to_i].remove_cards << run_data['items_purged'][idx]
    end

    run_data['potions_obtained'].each do |e|
      @floors[e['floor'].to_i].obtain_objects << e['key']
    end

    # StS本体のバグによる、戦闘後のカード選択画面を開いた回数分ログが重複して出力される問題の対処。
    @floors.each do |e|
      # TODO: 選択画面を何度も開いたのちにカードをピックした場合、uniqでは対処が不十分
      e.obtain_chosen_cards.uniq!
    end

    # MOD Relic Statsの情報を活用
    unless run_data['relic_stats'].nil?
      unless run_data['relic_stats']["Pandora's Box"].nil?
        obtain_floor = run_data['relic_stats']['obtain_stats'][0]["Pandora's Box"].to_i
        @floors[obtain_floor].obtain_objects += run_data['relic_stats']["Pandora's Box"]
      end
      unless run_data['relic_stats']['Astrolabe'].nil?
        obtain_floor = run_data['relic_stats']['obtain_stats'][0]['Astrolabe'].to_i
        @floors[obtain_floor].obtain_objects += run_data['relic_stats']['Astrolabe']
      end
      ['Whetstone', 'War Paint'].each do |b|
        unless run_data['relic_stats'][b].nil?
          obtain_floor = run_data['relic_stats']['obtain_stats'][0][b].to_i
          @floors[obtain_floor].upgrade_cards += run_data['relic_stats'][b]
        end
      end
      ['Bottled Frame', 'Bottled Lightning', 'Bottled Tornado'].each do |b|
        unless run_data['relic_stats'][b].nil?
          obtain_floor = run_data['relic_stats']['obtain_stats'][0][b].to_i
          @floors[obtain_floor].bottled_cards << run_data['relic_stats'][b]
        end
      end
    end
  end

  # 4205495799455053197 should convert to 18JIMLWZV7HTH
  # -3363429452019887060 should convert to 4G7UMG8L17P0W
  def convert_raw_seed_to_string(seed)
    char_string = '0123456789ABCDEFGHIJKLMNPQRSTUVWXYZ'

    # Convert to unsigned
    seed += 2**64 if seed.negative?
    leftover = seed
    char_count = char_string.size
    result = []
    while leftover != 0
      remainder = leftover % char_count
      leftover /= char_count
      index = remainder.to_i
      c = char_string[index]
      result << c
    end
    result.reverse.join
  end

  def generate_map(seed, path_taken, has_shoes, is_ascension_zero)
    result = Array.new(3){Array.new(15+14){Array.new(7+6){Array.new(2)}}}
    stdout = `bin/sts_map_oracle2 --seed "#{seed}" #{if is_ascension_zero then '-a' else '' end}`
    map_info = JSON.parse(stdout)

    # 以下を行う
    # - 部屋表記を正規化する(例: MonsterRoom -> M)
    # - path_takenの情報をもとに立ち寄った可能性のあるすべての部屋にフラグを立てる
    map_info.each_with_index do |map,act|
      map['nodes'].each do |node|
        node['class_r'] = case node['class']
                          when 'RestRoom'
                            'R'
                          when 'EventRoom'
                            '?'
                          when 'MonsterRoom'
                            'M'
                          when 'MonsterRoomElite'
                            'E'
                          when 'TreasureRoom'
                            'T'
                          when 'ShopRoom'
                            '$'
                          else
                            node['class']
                          end
        floor = act*16+node['y']+1
        node['visited']  = path_taken[floor-1] == node['class_r']
        node['defeated'] = path_taken.length == floor
      end
    end

    unless has_shoes then
      map_info.each do |map|
        flipped = true
        while flipped do
          flipped = false
          map['nodes'].filter{|n|n['visited'] && !n['defeated']}.each do |node|
            # すべての到達元が unvisitedであれば unvisited
            to = map['edges'].filter{|e|
              # 「先」が自身であるすべてのedge
              e['dst_x'] == node['x'] && e['dst_y'] == node['y']
            }
            if to != [] && to.all?{|e|
                # すべてのedgeの「元」がunvisitedである
                map['nodes'].find{|n|n['x'] == e['src_x'] && n['y'] == e['src_y']}['visited'] == false
              } then
              node['visited'] = false
              flipped = true
            end
            # すべての到達先が unvisitedであれば unvisited
            from = map['edges'].filter{|e|
              # 「元」が自身であるすべてのedge
              e['src_x'] == node['x'] && e['src_y'] == node['y']
            }
            if from != [] && from.all?{|e|
                # すべてのedgeの「先」がunvisitedである
                map['nodes'].find{|n|n['x'] == e['dst_x'] && n['y'] == e['dst_y']}['visited'] == false
              } then
              node['visited'] = false
              flipped = true
            end
          end
        end
      end
    end


    # JSON情報を元にマトリックス状のマップ情報を生成する
    map_info.each_with_index do |map,act|
      map['nodes'].each do |n|
        result[act][n['y']*2][n['x']*2][0] = n['class_r']
        result[act][n['y']*2][n['x']*2][1] = n['visited']
      end
      map['edges'].each do |e|
        case e['dst_x'] - e['src_x']
                when -1
                  result[act][e['src_y']*2+1][e['src_x']*2-1] = '\\'
                when 0
                  result[act][e['src_y']*2+1][e['src_x']*2] = '|'
                when 1
                  result[act][e['src_y']*2+1][e['src_x']*2+1] = '/'
                end
      end
    end

    return result
  end
end

class Report
  attr_accessor :author, :run_id, :title, :description, :key_cards, :key_cards_pos, :key_relics, :key_relics_pos, :password, :floor_comment, :run

  def initialize(author, run_id, report_summary, report_body = {}, run)
    @author        = author
    @run_id        = run_id
    @title         = report_summary.fetch('title', run_id)
    @description   = report_summary.fetch('description', '')
    @key_cards     = report_summary.fetch('key_cards', [])
    @key_cards_pos = report_summary.fetch('key_cards_pos', [])
    @key_relics    = report_summary.fetch('key_relics', [])
    @key_relics_pos = report_summary.fetch('key_relics_pos', [])
    @password       = report_body.fetch('password', '')
    @floor_comment = report_body.fetch('floor_comment', [])
    @run           = run
  end
end
