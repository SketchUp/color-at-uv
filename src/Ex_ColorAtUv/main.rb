require 'sketchup.rb'

module Example::ColorAtUv

  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins').add_submenu(EXTENSION[:name])
    menu.add_item('Pick Color') { self.pick_color_tool }
    menu.add_separator
    menu.add_item('Help...') { self.open_help }
    file_loaded(__FILE__)
  end

  def self.pick_color_tool
    Sketchup.active_model.select_tool(ColorPickerTool.new)
  end


  class ColorPickerTool

    def initialize
      @color = nil
    end

    def onMouseMove(flags, x, y, view)
      @color = pick_color(x, y, view)
    end

    private

    def pick_color(x, y, view)
      ray = view.pickray(x, y)
      global_point, instance_path = view.model.raytest(ray, true)
      return nil if global_point.nil?
      # The point is the world position where the pick hit something.
      # The instance path is an array that contains the entity that was hit,
      # last in the array, and the instances that contains it.
      face = instance_path.pop
      return nil unless face.is_a?(Sketchup::Face)
      # Determine if we picked teh front or backside.
      front = face.normal.dot(ray[1]) < 0.0
      material = (front) ? face.material : face.back_material
      return nil if material.nil?
      # We simply return the material color when the material have no texture.
      return material.color if material.texture.nil?
      # Using the picked point and the picked entity we can resolve the UV
      # coordinate picked.
      # First we must translate the globally picked point to the local space for
      # the face.
      # TODO: Double check the order of transformations multiplied is correct.
      to_global = instance_path.inject(IDENTITY) { |tr, instance|
        # The inject method will yield the result of the previous iteration in
        # the first parameter of the block; here "tr".
        # This accumulate the total transformation for all the instances in the
        # instance path.
        instance.transformation * tr
      }
      to_local = to_global.inverse
      local_point = global_point.transform(to_local)
      # Fetch a UVHelper for the front and backside.
      uvh = face.get_UVHelper(true, true)
      uvq = (front) ? uvh.get_front_UVQ(local_point) : uvh.get_back_UVQ(local_point)
      # Need to convert from UVQ to UV.
      u = uvq.x / uvq.z
      v = uvq.y / uvq.z
      view.tooltip = "U: #{u}, V: #{v}"
      # TODO: Uncomment once image_ref is hooked up.
      #image_rep = material.texture.image_ref
      #return image_rep.color_at_uv(u, v)
      # Alternative: As Array
      #return image_rep.color_at_uv([u, v])
      # Alternative: As Point3d (Often used elsewhere in the API)
      #return image_rep.color_at_uv(Geom::Point3d(u, v))
    end

  end # class


  def self.open_help
    UI.openURL(EXTENSION[:url])
  end

end # module
