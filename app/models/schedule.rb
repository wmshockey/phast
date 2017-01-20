class Schedule < ActiveRecord::Base
    belongs_to :simulation
    has_many :activities, dependent: :destroy
    validates :name, :presence => true
    validates :description, allow_blank: true, length: { maximum: 512 }
    validates :start_date, :presence => true
    validates :period, :presence => true, numericality: {:greather_than_or_equal_to => 0, :less_than => 366}
    validates :pipeline_id, :presence => true
    validates :sched_type, :presence => true, inclusion: { in: %w(PRIOR PRELIMINARY SIMULATED), message: "%{value} is not a valid schedule type" }


    def initialize_batch_sequence(prior_activities, statar)
#     Get list of batches listed in the prior period schedule
      batch_list = prior_activities.map {|p| p.batch_id}.uniq
#     Find list of batches that have already been delivered out of the line
      prior_deliveries = prior_activities.select {|p| (p.activity_type == "DELIVERY" or p.activity_type == "LANDING") and !p.end_time.nil? }
      remove_list = prior_deliveries.map {|p| p.batch_id}.uniq
      batch_list.reject! {|p| remove_list.include?(p) }
      if batch_list.empty?
        raise "The prior schedule shows all batches as being delivered"
      end        
#     Proceed to populate the batch sequence array
      max_batches = batch_list.count
      max_stations = statar.count
      bs = Array.new(statar.count){Array.new(max_batches)}
      batch_list.each do |b|
        batch_id = b
        batch_ix = batch_list.index(b)
        batch_activities = prior_activities.select {|p| p.batch_id == b}
        start_rec = batch_activities.find {|b| (b.activity_type == "INJECTION" or b.activity_type =="RECEIPT") }
        end_rec = batch_activities.find {|b| (b.activity_type == "DELIVERY" or b.activity_type == "LANDING") }
        if start_rec.nil? then
          start_rec = end_rec.dup
          start_ix = 0
          end_ix = statar.index {|s| s.name == end_rec.station}
          start_rec.station = statar[0].name
          start_rec.activity_type = "INJECTION"
        elsif end_rec.nil?
          end_rec = start_rec.dup
          start_ix = statar.index {|s| s.name == start_rec.station}
          end_ix = max_stations-1
          end_rec.station = statar[max_stations-1].name
          end_rec.activity_type = "DELIVERY"
          end_rec.volume = 0.0
        else 
          start_ix = statar.index {|s| s.name == start_rec.station}
          end_ix = statar.index {|s| s.name == end_rec.station}
        end
        batch_temp = batch_id.partition("-")
        commodity_id = batch_temp[0]
        batch_number = batch_temp[2].partition(" ")[0]
        for ix in (0...max_stations)
          bs[ix][batch_ix] = Batchrec.new(batch_number, commodity_id, 0.0, start_rec.station, end_rec.station, nil, nil, nil, start_rec.shipper, start_rec.nomination_name)
          bs[ix][batch_ix].batch_id = commodity_id + "-" + batch_number.to_s.rjust(5, "0")
        end        
        for ix in (0...start_ix)
          bs[ix][batch_ix].volume = 0.0
        end
        for ix in (end_ix...max_stations)
          bs[ix][batch_ix].volume = 0.0
        end
        bs[start_ix][batch_ix].volume = start_rec.volume
        bs[start_ix][batch_ix].start_time = start_rec.start_time
        bs[start_ix][batch_ix].end_time = start_rec.end_time
        bs[start_ix][batch_ix].activity_type = start_rec.activity_type
        for ix in (start_ix+1...end_ix)
          bs[ix][batch_ix].volume = start_rec.volume
          bs[ix][batch_ix].activity_type = "EVEN"
        end
        bs[end_ix][batch_ix].volume = end_rec.volume
        bs[end_ix][batch_ix].start_time = end_rec.start_time
        bs[end_ix][batch_ix].end_time = end_rec.end_time
        bs[end_ix][batch_ix].activity_type = end_rec.activity_type
      end
#     Record the sequence volumes in the station array (statar)
      statar.each_with_index do |s, stn_ix|
        bs[stn_ix].each do |b|
          s.sequence_volume = s.sequence_volume + b.volume
        end
      end
#     Find the initial starting time for the simulation.  This is taken to be the latest end time of the prior month's scheduled injections out of the first station.
      event_end_times = bs[0].map {|b| b.end_time}
      event_end_times.select! { |x| !x.nil? }
      if event_end_times.nil?
        self.errors.add(:base, "There are no activity end times in the prior schedule on which to base the simulation start time.  Will use default value of 2001-Jan-01 00:00")
        logger.error("There are no activity end times in the prior schedule on which to base the simulation start time.  Will use default value of 2001-Jan-01 00:00")
        initial_start_time = Datetime.new(2000,1,1)
      else
        initial_start_time = event_end_times.max
      end
      return bs, initial_start_time      
    rescue Exception => e
      logger.error(e.message)
      self.errors.add(:base, e.message)
    end


    def finalize_batch_sequence(max_batchsize, btsqar, nomination_name, shipments, statar)
#     Break up shipments into a list of batches
      batches = Array.new
      number_of_shipments = shipments.count
      total_volume_of_shipments = shipments.sum("volume")
      total_number_of_batches = total_volume_of_shipments / max_batchsize
      shipments.each_with_index do |s, ix|
        number_of_batches_in_shipment = s.volume / max_batchsize
        spacing_of_batches = (total_number_of_batches / number_of_batches_in_shipment).round
        vol = s.volume
        batch_number_within_shipment = 0
        while vol > max_batchsize
          batch_number = (ix+1) + batch_number_within_shipment * spacing_of_batches
          batches << Batchrec.new(batch_number, s.commodity_id, max_batchsize, s.start_location, s.end_location, nil, nil, nil, s.shipper, nomination_name)
          vol = vol - max_batchsize
          batch_number_within_shipment = batch_number_within_shipment + 1
        end
        if vol > 0.0 then
          batch_number = (ix+1) + batch_number_within_shipment * spacing_of_batches
          batches << Batchrec.new(batch_number, s.commodity_id, vol, s.start_location, s.end_location, nil, nil, nil, s.shipper, nomination_name)
        end
      end
#     Re-order the batches by batch_number to spread shipment batches out over the month for best ratability and assign batch id's for each.
#     Give newly nominated batches a batch number starting at 10000 to distinguish them from old batches previously in the line from prior schedule.
      batches.sort! { |a, b| a.batch_number <=> b.batch_number }
      batches.each_with_index do |b, bix|
        b.batch_number = 10000 + bix + 1
        b.batch_id = b.commodity_id + "-" + b.batch_number.to_s.rjust(5, "0")
      end
#     Create the two-dimensional batch sequence array
      max_batches = batches.count
      bs = Array.new(statar.count){Array.new(max_batches)}
      batches.each_with_index do |b, btix|
        start_loc = b.start_location
        station_rec = statar.detect {|s| s.name == start_loc}
        start_kmp = station_rec.kmp
        end_loc = b.end_location
        station_rec = statar.detect {|s| s.name == end_loc}
        end_kmp = station_rec.kmp
        statar.each_with_index do |s, stix|
          stat = s.name
          kmp = s.kmp
          if start_kmp <= kmp and end_kmp > kmp then
            batch_rec = batches[btix].dup
            if statar[stix].name == start_loc then
              batch_rec.activity_type = "INJECTION"
            else
              batch_rec.activity_type = "EVEN"
            end
            bs[stix][btix] = batch_rec
          else
            batch_rec = batches[btix].dup
            if statar[stix].name == end_loc then
              batch_rec.activity_type = "DELIVERY"
              bs[stix][btix] = batch_rec
              bs[stix][btix].volume = 0.0
            else
              bs[stix][btix] = batch_rec
              bs[stix][btix].volume = 0.0
            end
          end
          s.sequence_volume = s.sequence_volume + bs[stix][btix].volume
        end
      end
#     Now tack the new batches from the nomination shipments onto the front end of the existing batch sequence array btsqar
#     The new month batches are tacked onto the front end of the sequence because the initial linefill starts with the last batch of the sequence downstream of the first station
#     and we want those to be from the prior period schedule batches.
      number_of_prior_batches = btsqar[0].length
      final_bs = Array.new(statar.count){Array.new(max_batches + number_of_prior_batches)}
      statar.each_with_index do |s, stix|
        final_bs[stix] = bs[stix] + btsqar[stix]
      end
      return final_bs
    end
    
    def clean_batch_sequence(btsqar)
#   Remove batches from the batch sequence if they have no activity during the simulation.  (e.g. prior schedule batches that were not initially in the line)
      batch_ix = 0
      num_stations = btsqar.length
      num_batches = btsqar[0].length
      while batch_ix < num_batches
        active = false
        stn_ix = 0
        while stn_ix < num_stations
          if btsqar[stn_ix][batch_ix].start_time or btsqar[stn_ix][batch_ix].end_time then
            active = true
          end
          stn_ix = stn_ix + 1
        end
        if not active then
          btsqar.map {|row| row.delete_at(batch_ix) }
          num_batches = num_batches - 1
        else
          batch_ix = batch_ix + 1
        end
      end
    end

end